Shader "Custom/Rain/RaindropSDF"
{
    Properties
    {
        [Header(Drop Shape)]
        _PositionX          ("Center X  (0=left  1=right)",    Range(0,1))         = 0.5
        _PositionY          ("Center Y  (0=bottom 1=top)",     Range(0,1))         = 0.5
        _DropRadius         ("Drop Radius (pixels)",            Range(8, 512))      = 80.0
        _DropAspect         ("Width / Height ratio",            Range(0.4, 1.6))    = 0.88
        _GravityFlattening  ("Gravity Sag (bottom flatter)",    Range(0.0, 0.6))    = 0.16

        [Header(Wettability - contact line irregularity)]
        // Simulates contact-angle hysteresis: the drop edge pins and releases
        // at microscopic surface features, producing an irregular contact line.
        _WettabilityStrength("Irregularity Strength",           Range(0.0, 0.55))   = 0.20
        _WettabilityScale   ("Irregularity Frequency",          Range(0.5, 8.0))    = 2.8
        _WettabilitySeed    ("Shape Seed",                      Float)              = 0.0

        [Header(Optics)]
        _IOR                ("Index of Refraction (water=1.333)", Range(1.0, 1.8))  = 1.333
        _LensThickness      ("Lens Thickness (affects refraction)", Range(0.0, 1.0))= 0.55
        _ChromaticAberration("Chromatic Aberration",            Range(0.0, 0.025))  = 0.005
        _DropTint           ("Water Tint (A = tint strength)",  Color)              = (0.82, 0.93, 1.0, 0.07)
        _Transparency       ("Transparency (1=fully clear)",    Range(0.0, 1.0))    = 0.92

        [Header(Lighting)]
        _LightDirX          ("Light Dir X (-1 left  +1 right)", Range(-1.0, 1.0))  = -0.35
        _LightDirY          ("Light Dir Y (-1 down  +1 up)",    Range(-1.0, 1.0))  =  0.65
        _FresnelStrength    ("Fresnel Rim Strength",            Range(0.0, 2.0))    = 0.85
        _FresnelPower       ("Fresnel Power",                   Range(1.0, 10.0))   = 3.5
        _SpecularStrength   ("Specular Strength",               Range(0.0, 6.0))    = 2.5
        _SpecularSharpness  ("Specular Sharpness",              Range(8, 512))      = 128.0
        _SpecularColor      ("Specular / Rim Color",            Color)              = (1.0, 1.0, 1.0, 1.0)

        [Header(Caustic and Meniscus)]
        // Caustic: bright annular ring where the convex lens focuses transmitted light.
        _CausticStrength    ("Caustic Ring Strength",           Range(0.0, 3.0))    = 0.65
        _CausticRadius      ("Caustic Ring Radius (normalised)", Range(0.3, 0.98))  = 0.72
        _CausticWidth       ("Caustic Ring Width",              Range(0.01, 0.25))  = 0.07
        // Meniscus: bright crescent rim at the air-water-glass contact line.
        _MeniscusStrength   ("Meniscus Rim Brightness",         Range(0.0, 3.0))    = 0.50
        _MeniscusWidth      ("Meniscus Width",                  Range(0.002, 0.1))  = 0.02
        _EdgeSoftness       ("Edge Softness (pixels)",          Range(0.3, 4.0))    = 1.5
    }

    SubShader
    {
        Tags
        {
            "RenderType"     = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
        }

        Blend Off
        Cull Off
        ZWrite Off
        ZTest Always

        Pass
        {
            Name "RaindropSDF"

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment frag
            #pragma target 3.5

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float  _PositionX;
                float  _PositionY;
                float  _DropRadius;
                float  _DropAspect;
                float  _GravityFlattening;
                float  _WettabilityStrength;
                float  _WettabilityScale;
                float  _WettabilitySeed;
                float  _IOR;
                float  _LensThickness;
                float  _ChromaticAberration;
                float4 _DropTint;
                float  _Transparency;
                float  _LightDirX;
                float  _LightDirY;
                float  _FresnelStrength;
                float  _FresnelPower;
                float  _SpecularStrength;
                float  _SpecularSharpness;
                float4 _SpecularColor;
                float  _CausticStrength;
                float  _CausticRadius;
                float  _CausticWidth;
                float  _MeniscusStrength;
                float  _MeniscusWidth;
                float  _EdgeSoftness;
            CBUFFER_END

            // ── Noise helpers ──────────────────────────────────────────────────

            float hash1(float2 p)
            {
                return frac(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
            }

            float valueNoise(float2 p)
            {
                float2 i = floor(p);
                float2 f = frac(p);
                float2 u = f * f * (3.0 - 2.0 * f);   // smoothstep
                return lerp(lerp(hash1(i),               hash1(i + float2(1, 0)), u.x),
                            lerp(hash1(i + float2(0, 1)), hash1(i + float2(1, 1)), u.x), u.y);
            }

            // ── 3-octave domain warp for wettability (contact-line roughness) ──
            //
            // Models contact-angle hysteresis: the triple-phase boundary (air /
            // water / glass) is pinned by nanoscale surface heterogeneities.
            // Three FBM octaves produce coarse pinning blobs (low freq),
            // medium roughness, and fine micro-detail.
            //
            // Returns a displacement vector in drop-local normalised space.
            float2 WarpDomain(float2 p, float scale, float seed)
            {
                float2 s  = seed * float2(1.0, 1.618);

                // Octave 1 — large pinning features (blobs, 0.5–1 drop-radii)
                float2 p1 = p * scale + s;
                float2 w  = float2(valueNoise(p1),
                                   valueNoise(p1 + float2(5.2, 1.3))) * 2.0 - 1.0;

                // Octave 2 — medium surface roughness
                float2 p2 = p * (scale * 2.1) + s + float2(3.7, 8.1);
                w        += 0.5 * (float2(valueNoise(p2),
                                          valueNoise(p2 + float2(5.2, 1.3))) * 2.0 - 1.0);

                // Octave 3 — fine contact-line micro-detail
                float2 p3 = p * (scale * 4.3) + s + float2(6.2, 2.9);
                w        += 0.25 * (float2(valueNoise(p3),
                                           valueNoise(p3 + float2(5.2, 1.3))) * 2.0 - 1.0);

                return w / 1.75;    // normalise combined energy
            }

            // ── Fragment shader ────────────────────────────────────────────────

            half4 frag(Varyings IN) : SV_Target
            {
                float2 screenUV = IN.texcoord;
                float  screenW  = _ScreenParams.x;
                float  screenH  = _ScreenParams.y;
                float4 scene    = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, screenUV);

                // Guard: _ScreenParams = (1,1) during some early URP blit passes
                if (screenW < 2.0 || screenH < 2.0)
                    return half4(scene.rgb, 1.0);

                // ── Step 1: drop-local normalised coordinate ───────────────────
                //
                // p = (0,0) at the drop centre.  |p| ≈ 1 at the unperturbed edge.
                // We work in this space for all SDF and optics calculations.
                float2 delta  = (screenUV - float2(_PositionX, _PositionY))
                              * float2(screenW, screenH);
                float2 p      = delta / max(_DropRadius, 1.0);
                p.x          /= max(_DropAspect, 0.01);

                // ── Step 2: gravity deformation ────────────────────────────────
                //
                // A sessile drop on a vertical window sags under gravity:
                //   • bottom edge is wider/flatter (contact area spreads downward)
                //   • top edge is slightly more pointed
                //
                // Transform: y_shaped = y * (1 + g*y)
                //   • p.y > 0 (top):    y grows faster  → top is elongated / pointed
                //   • p.y < 0 (bottom): y shrinks       → SDF sees bottom as "closer to
                //                         centre" → screen boundary pushed outward → wider
                //
                // A small downward bias (– g * 0.15) shifts the effective centre
                // downward, making the drop appear to sag.
                float2 shapeP;
                shapeP.x = p.x;
                shapeP.y = p.y * (1.0 + _GravityFlattening * p.y)
                         - _GravityFlattening * 0.15;

                // ── Step 3: wettability domain warp (contact-line irregularity) ─
                //
                // The warp is strongest exactly at the contact line (r ≈ 1) and
                // falls off quickly inside and outside, so the interior of the drop
                // remains smooth (preserving refraction quality).
                float  rShape     = length(shapeP);
                float  edgeWeight = exp(-((rShape - 1.0) * (rShape - 1.0)) / 0.09);
                float2 warpOff    = WarpDomain(shapeP, _WettabilityScale, _WettabilitySeed)
                                  * _WettabilityStrength * edgeWeight;
                float2 warpedP    = shapeP + warpOff;

                // ── Step 4: SDF and anti-aliased coverage mask ─────────────────
                float sdf    = length(warpedP) - 1.0;
                float pixSz  = 1.0 / max(_DropRadius, 1.0);
                float aaW    = _EdgeSoftness * pixSz;
                float mask   = 1.0 - smoothstep(-aaW, aaW, sdf);

                // Early-out: pixel is outside the drop
                if (mask < 0.001)
                    return half4(scene.rgb, 1.0);

                // ── Step 5: height field — paraboloid spherical-cap model ──────
                //
                // Real sessile drops have a spherical-cap cross-section determined
                // by the contact angle θ.  We approximate with a paraboloid:
                //   h(r) = 1 - r²      (1 at centre, 0 at edge)
                //
                // This is a first-order match to a spherical cap for small θ.
                // The gradient ∇h = -2·shapeP encodes the surface slope.
                //
                // We use unwarped shapeP (not warpedP) so the normals are smooth —
                // optical refraction should not follow contact-line micro-roughness.
                float  rSq     = dot(shapeP, shapeP);
                float  r       = sqrt(rSq);
                float  h       = saturate(1.0 - rSq);      // thickness proxy [0,1]
                float2 gradH   = -2.0 * shapeP;            // ∇(1 - r²) = -2·p

                // Convert gradient from drop-local → screen-UV space
                float2 screenGrad = float2(gradH.x / max(_DropAspect, 0.01), gradH.y)
                                  / max(_DropRadius, 1.0);

                // ── Step 6: refraction (thin-lens model) ───────────────────────
                //
                // Snell's law in the thin-lens limit:
                //   offset ≈ n̂_xy · h · (IOR − 1) · thickness_scale
                //
                // Larger offset at the centre (thickest), zero at the edge.
                float  refrScale = h * _LensThickness * (_IOR - 1.0) * 0.07;
                float2 refrOff   = screenGrad * refrScale;

                // Chromatic aberration: water has slightly different IOR per wavelength.
                //   Red  bends most  (longer path length)
                //   Blue bends least
                float2 uvR = clamp(screenUV + refrOff * (1.0 + _ChromaticAberration), 0.001, 0.999);
                float2 uvG = clamp(screenUV + refrOff,                                0.001, 0.999);
                float2 uvB = clamp(screenUV + refrOff * (1.0 - _ChromaticAberration), 0.001, 0.999);

                float3 refracted;
                refracted.r = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uvR).r;
                refracted.g = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uvG).g;
                refracted.b = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uvB).b;

                // Water tint: slight blue cast, proportional to optical path (h)
                refracted = lerp(refracted, _DropTint.rgb, _DropTint.a * h);

                // ── Step 7: 3-D surface normal ─────────────────────────────────
                //
                // The height field h gives a surface z = h(x,y).
                // The outward normal is proportional to (-∂h/∂x, -∂h/∂y, 1).
                // We weight the z component by 1/LensThickness so that thicker drops
                // have flatter surfaces (shallower normals) near the centre, matching
                // real geometry.
                float3 N = normalize(float3(
                    gradH.x / max(_DropAspect, 0.01),   // undo aspect
                    gradH.y,
                    1.0 / max(_LensThickness, 0.01)      // flatter = thicker
                ));
                // N points outward (away from glass, toward camera) — correct.

                // ── Step 8: Fresnel (edge rim darkening / brightening) ─────────
                //
                // At grazing incidence (edge of drop), Fresnel reflectance → 1.
                // At normal incidence (centre), Fresnel ≈ ((n-1)/(n+1))² ≈ 0.02 for water.
                float3 V       = float3(0, 0, 1);                    // view = straight on
                float  cosTheta = saturate(dot(N, V));
                float  fresnel  = pow(1.0 - cosTheta, _FresnelPower)
                               * _FresnelStrength * mask;

                // ── Step 9: specular highlight (Blinn-Phong) ───────────────────
                float3 L    = normalize(float3(_LightDirX, _LightDirY, 0.7));
                float3 H    = normalize(L + V);
                float  spec = pow(saturate(dot(N, H)), max(_SpecularSharpness, 1.0))
                            * _SpecularStrength * mask;

                // ── Step 10: caustic ring ──────────────────────────────────────
                //
                // A convex plano-convex lens (spherical drop) focuses transmitted
                // light to an annular caustic at a radius ≈ 0.7 of the drop.
                // We render this as a Gaussian ring that brightens the scene below.
                float causticArg = (r - _CausticRadius) / max(_CausticWidth, 0.001);
                float caustic    = exp(-causticArg * causticArg) * _CausticStrength * mask;

                // ── Step 11: meniscus rim ──────────────────────────────────────
                //
                // At the contact line (air / water / glass triple junction),
                // total-internal reflection and curvature produce a bright crescent
                // rim just inside the drop edge.  Modelled as a Gaussian on the SDF.
                float menArg   = sdf / max(_MeniscusWidth, 0.001);
                float meniscus = exp(-menArg * menArg) * _MeniscusStrength * mask;

                // ── Step 12: approximate scene reflection ──────────────────────
                //
                // A horizontal mirror of the scene approximates the environment
                // visible in the curved drop surface (window reflections).
                float2 reflUV   = clamp(float2(1.0 - screenUV.x, screenUV.y), 0.001, 0.999);
                float3 reflected = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, reflUV).rgb;

                // ── Step 13: composite ─────────────────────────────────────────
                //
                // Interior: weighted blend of refraction and reflection.
                //   Centre (cosTheta≈1, fresnel≈0) → mostly refracted scene (clear).
                //   Edge   (cosTheta≈0, fresnel≈1) → mostly reflection (mirror-like).
                float3 dropColor = lerp(refracted, reflected, saturate(fresnel * 0.35));

                // Caustic: additive brightening inside the drop where lens focuses
                dropColor += caustic * float3(0.92, 0.96, 1.0) * 0.4;

                // Blend drop over scene based on mask and transparency
                float  dropAlpha = mask * _Transparency;
                float3 finalRGB  = lerp(scene.rgb, dropColor, dropAlpha);

                // Additive features: sit on top of the composited result
                finalRGB += spec      * _SpecularColor.rgb;            // sharp highlight
                finalRGB += meniscus  * _SpecularColor.rgb * 0.6;     // contact-line rim

                return half4(finalRGB, 1.0);
            }
            ENDHLSL
        }
    }
}
