Shader "Custom/Rain/RaindropSDFTrail"
{
    // ── Overview ──────────────────────────────────────────────────────────────
    //
    // Renders a single sliding raindrop composed of TWO physically distinct parts:
    //
    //   1. MAIN DROP  — the current drop body at (PositionX, PositionY).
    //                   Round-ish, full opacity, strong refraction.
    //
    //   2. TRAIL BLOB — the residual water film left behind as the drop slides.
    //                   Identified via the gravity-quadratic fold (p.y below the
    //                   parabola vertex), given an independent shape, aspect,
    //                   wettability seed, opacity and specular response.
    //
    // The two parts are differentiated BEFORE the quadratic is applied (using the
    // raw drop-local p.y) so their wettability warps receive different seeds and
    // parameters — producing genuinely different contact-line shapes.
    //
    // Physical effects retained from RaindropSDF:
    //   • Gravity sag (quadratic coordinate warp)
    //   • Contact-angle hysteresis (3-octave FBM domain warp at contact line)
    //   • Paraboloid height field → smooth surface normals
    //   • Thin-lens refraction with chromatic aberration
    //   • Fresnel rim, Blinn-Phong specular
    //   • Caustic ring, meniscus rim
    //   • Approximate scene reflection
    //
    // To animate sliding: drive _PositionY from C# over time.
    // The trail appears automatically below the drop whenever GravitySag > 0.

    Properties
    {
        [Header(Drop Position and Shape)]
        _PositionX          ("Center X  (0=left  1=right)",       Range(0,1))         = 0.5
        _PositionY          ("Center Y  (0=bottom 1=top)",        Range(0,1))         = 0.7
        _DropRadius         ("Drop Radius (pixels)",               Range(8, 512))      = 80.0
        _DropAspect         ("Drop Width / Height ratio",          Range(0.3, 1.6))    = 0.82
        _GravityFlattening  ("Gravity Sag  (also controls trail distance)", Range(0.01, 0.6)) = 0.18

        [Header(Drop Wettability)]
        _WettabilityStrength("Drop Irregularity Strength",         Range(0.0, 0.55))   = 0.22
        _WettabilityScale   ("Drop Irregularity Frequency",        Range(0.5, 8.0))    = 2.8
        _WettabilitySeed    ("Drop Shape Seed",                    Float)              = 0.0

        [Header(Trail Blob Shape)]
        // The trail is the phantom created by the gravity-quadratic fold.
        // It sits below the main drop in screen space.
        _TrailAspect        ("Trail Width / Height ratio",         Range(0.1, 1.2))    = 0.38
        _TrailStretch       ("Trail Y Stretch (elongation)",       Range(0.5, 4.0))    = 1.6

        [Header(Trail Wettability - independent shape)]
        _TrailWettabilityStrength("Trail Irregularity Strength",   Range(0.0, 0.75))   = 0.42
        _TrailWettabilityScale   ("Trail Irregularity Frequency",  Range(0.5, 12.0))   = 4.5
        _TrailWettabilitySeed    ("Trail Shape Seed",              Float)              = 47.3

        [Header(Trail Optics)]
        _TrailOpacity       ("Trail Opacity",                      Range(0.0, 1.0))    = 0.55
        _TrailIOR           ("Trail IOR (thinner film = lower)",   Range(1.0, 1.5))    = 1.18
        _TrailLensThickness ("Trail Lens Thickness",               Range(0.0, 0.6))    = 0.20
        _TrailSpecularScale ("Trail Specular Scale (0=none)",      Range(0.0, 1.0))    = 0.30

        [Header(Shared Optics)]
        _IOR                ("Drop IOR (water = 1.333)",           Range(1.0, 1.8))    = 1.333
        _LensThickness      ("Drop Lens Thickness",                Range(0.0, 1.0))    = 0.55
        _ChromaticAberration("Chromatic Aberration",               Range(0.0, 0.025))  = 0.005
        _DropTint           ("Water Tint (A = strength)",          Color)              = (0.82, 0.93, 1.0, 0.07)
        _Transparency       ("Drop Transparency",                  Range(0.0, 1.0))    = 0.92

        [Header(Lighting)]
        _LightDirX          ("Light Dir X",                        Range(-1.0, 1.0))   = -0.35
        _LightDirY          ("Light Dir Y",                        Range(-1.0, 1.0))   =  0.65
        _FresnelStrength    ("Fresnel Rim Strength",               Range(0.0, 2.0))    = 0.85
        _FresnelPower       ("Fresnel Power",                      Range(1.0, 10.0))   = 3.5
        _SpecularStrength   ("Specular Strength",                  Range(0.0, 6.0))    = 2.5
        _SpecularSharpness  ("Specular Sharpness",                 Range(8, 512))      = 128.0
        _SpecularColor      ("Specular / Rim Color",               Color)              = (1.0, 1.0, 1.0, 1.0)

        [Header(Caustic and Meniscus)]
        _CausticStrength    ("Caustic Ring Strength",              Range(0.0, 3.0))    = 0.65
        _CausticRadius      ("Caustic Ring Radius",                Range(0.3, 0.98))   = 0.72
        _CausticWidth       ("Caustic Ring Width",                 Range(0.01, 0.25))  = 0.07
        _MeniscusStrength   ("Meniscus Rim Brightness",            Range(0.0, 3.0))    = 0.50
        _MeniscusWidth      ("Meniscus Width",                     Range(0.002, 0.1))  = 0.02
        _EdgeSoftness       ("Edge Softness (pixels)",             Range(0.3, 4.0))    = 1.5
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
            Name "RaindropSDFTrail"

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
                float  _TrailAspect;
                float  _TrailStretch;
                float  _TrailWettabilityStrength;
                float  _TrailWettabilityScale;
                float  _TrailWettabilitySeed;
                float  _TrailOpacity;
                float  _TrailIOR;
                float  _TrailLensThickness;
                float  _TrailSpecularScale;
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

            // ── Noise ──────────────────────────────────────────────────────────

            float hash1(float2 p)
            {
                return frac(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
            }

            float valueNoise(float2 p)
            {
                float2 i = floor(p);
                float2 f = frac(p);
                float2 u = f * f * (3.0 - 2.0 * f);
                return lerp(lerp(hash1(i),               hash1(i + float2(1, 0)), u.x),
                            lerp(hash1(i + float2(0, 1)), hash1(i + float2(1, 1)), u.x), u.y);
            }

            // 3-octave FBM domain warp — models contact-angle hysteresis.
            // Returns displacement in drop-local normalised space.
            float2 WarpDomain(float2 p, float scale, float seed)
            {
                float2 s  = seed * float2(1.0, 1.618);

                float2 p1 = p * scale + s;
                float2 w  = float2(valueNoise(p1),
                                   valueNoise(p1 + float2(5.2, 1.3))) * 2.0 - 1.0;

                float2 p2 = p * (scale * 2.1) + s + float2(3.7, 8.1);
                w        += 0.5 * (float2(valueNoise(p2),
                                          valueNoise(p2 + float2(5.2, 1.3))) * 2.0 - 1.0);

                float2 p3 = p * (scale * 4.3) + s + float2(6.2, 2.9);
                w        += 0.25 * (float2(valueNoise(p3),
                                           valueNoise(p3 + float2(5.2, 1.3))) * 2.0 - 1.0);

                return w / 1.75;
            }

            // ── Shared optics sub-routine ──────────────────────────────────────
            //
            // Given a drop-local shapeP (smooth, unwarped) and an SDF mask,
            // compute refraction UVs, surface normal, Fresnel, specular, caustic.
            //
            // ior, lensThickness, specStrength, specSharpness are passed in so
            // the trail can use different values from the main drop.
            //
            // Returns:
            //   out float3 refracted   — refracted + tinted scene colour
            //   out float3 N           — surface normal
            //   out float  fresnel
            //   out float  spec
            //   out float  caustic
            void ComputeOptics(
                float2 screenUV,
                float2 shapeP,          // smooth drop-local coords (unwarped)
                float  dropAspect,
                float  dropRadius,
                float  mask,
                float  ior,
                float  lensThickness,
                float  specStrength,
                float  specSharpness,
                out float3 refracted,
                out float3 N,
                out float  fresnel,
                out float  spec,
                out float  caustic)
            {
                float  rSq    = dot(shapeP, shapeP);
                float  r      = sqrt(rSq);
                float  h      = saturate(1.0 - rSq);
                float2 gradH  = -2.0 * shapeP;

                float2 screenGrad = float2(gradH.x / max(dropAspect, 0.01), gradH.y)
                                  / max(dropRadius, 1.0);

                // Thin-lens refraction
                float  refrScale = h * lensThickness * (ior - 1.0) * 0.07;
                float2 refrOff   = screenGrad * refrScale;

                float2 uvR = clamp(screenUV + refrOff * (1.0 + _ChromaticAberration), 0.001, 0.999);
                float2 uvG = clamp(screenUV + refrOff,                                0.001, 0.999);
                float2 uvB = clamp(screenUV + refrOff * (1.0 - _ChromaticAberration), 0.001, 0.999);

                refracted.r = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uvR).r;
                refracted.g = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uvG).g;
                refracted.b = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uvB).b;
                refracted   = lerp(refracted, _DropTint.rgb, _DropTint.a * h);

                // Surface normal from paraboloid height field
                N = normalize(float3(
                    gradH.x / max(dropAspect, 0.01),
                    gradH.y,
                    1.0 / max(lensThickness, 0.01)
                ));

                float3 V      = float3(0, 0, 1);
                float  cosT   = saturate(dot(N, V));
                fresnel       = pow(1.0 - cosT, _FresnelPower) * _FresnelStrength * mask;

                float3 L    = normalize(float3(_LightDirX, _LightDirY, 0.7));
                float3 H    = normalize(L + V);
                spec        = pow(saturate(dot(N, H)), max(specSharpness, 1.0))
                            * specStrength * mask;

                // Caustic ring
                float causticArg = (r - _CausticRadius) / max(_CausticWidth, 0.001);
                caustic          = exp(-causticArg * causticArg) * _CausticStrength * mask;
            }

            // ── Fragment ───────────────────────────────────────────────────────

            half4 frag(Varyings IN) : SV_Target
            {
                float2 screenUV = IN.texcoord;
                float  screenW  = _ScreenParams.x;
                float  screenH  = _ScreenParams.y;
                float4 scene    = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, screenUV);

                if (screenW < 2.0 || screenH < 2.0)
                    return half4(scene.rgb, 1.0);

                float pixSz = 1.0 / max(_DropRadius, 1.0);
                float aaW   = _EdgeSoftness * pixSz;

                // ── Raw drop-local coordinate ──────────────────────────────────
                // p = (0,0) at drop centre, |p| ≈ 1 at unperturbed edge.
                float2 delta = (screenUV - float2(_PositionX, _PositionY))
                             * float2(screenW, screenH);
                float2 p     = delta / max(_DropRadius, 1.0);
                p.x         /= max(_DropAspect, 0.01);

                // ── Branch discriminant ────────────────────────────────────────
                // The gravity parabola has its vertex at p.y = -1/(2g).
                // Pixels with p.y ABOVE the vertex belong to the main drop branch.
                // Pixels BELOW the vertex belong to the trail-fold branch.
                //
                // We compute this BEFORE applying the quadratic so that the two
                // branches can receive independent wettability parameters.
                float vertexY   = -1.0 / (2.0 * max(_GravityFlattening, 0.001));
                bool  isTrail   = (p.y < vertexY);

                // ── Gravity quadratic ──────────────────────────────────────────
                float2 shapeP;
                shapeP.x = p.x;
                shapeP.y = p.y * (1.0 + _GravityFlattening * p.y)
                         - _GravityFlattening * 0.15;

                // ── Per-branch aspect and stretch ──────────────────────────────
                // The trail should appear narrower and vertically elongated.
                // We rescale shapeP AFTER the quadratic so the SDF geometry changes
                // without affecting where the vertex/fold falls.
                float2 branchP;
                if (isTrail)
                {
                    // Remap X wider (smaller aspect = narrower pixel footprint, but
                    // dividing by TrailAspect makes the SDF circle appear narrower).
                    branchP.x = shapeP.x / max(_TrailAspect, 0.01) * max(_DropAspect, 0.01);
                    // Compress Y so the SDF stretches vertically in screen space.
                    branchP.y = shapeP.y / max(_TrailStretch, 0.01);
                }
                else
                {
                    branchP = shapeP;
                }

                // ── Wettability domain warp ────────────────────────────────────
                // Applied only near the contact line (edgeWeight falls off ∝ exp).
                // Trail and main drop use DIFFERENT seeds → different random shapes.
                float  rBranch    = length(branchP);
                float  edgeW      = exp(-((rBranch - 1.0) * (rBranch - 1.0)) / 0.09);

                float2 warpOff;
                if (isTrail)
                {
                    warpOff = WarpDomain(branchP,
                                         _TrailWettabilityScale,
                                         _TrailWettabilitySeed)
                            * _TrailWettabilityStrength * edgeW;
                }
                else
                {
                    warpOff = WarpDomain(branchP,
                                         _WettabilityScale,
                                         _WettabilitySeed)
                            * _WettabilityStrength * edgeW;
                }

                float2 warpedP = branchP + warpOff;

                // ── SDF mask ───────────────────────────────────────────────────
                float sdf  = length(warpedP) - 1.0;
                float mask = 1.0 - smoothstep(-aaW, aaW, sdf);

                if (mask < 0.001)
                    return half4(scene.rgb, 1.0);

                // ── Optics — different parameters per branch ───────────────────
                float3 refracted, N;
                float  fresnel, spec, caustic;

                if (isTrail)
                {
                    ComputeOptics(
                        screenUV, branchP,
                        _TrailAspect, _DropRadius,
                        mask,
                        _TrailIOR, _TrailLensThickness,
                        _SpecularStrength * _TrailSpecularScale,
                        _SpecularSharpness,
                        refracted, N, fresnel, spec, caustic);
                }
                else
                {
                    ComputeOptics(
                        screenUV, branchP,
                        _DropAspect, _DropRadius,
                        mask,
                        _IOR, _LensThickness,
                        _SpecularStrength, _SpecularSharpness,
                        refracted, N, fresnel, spec, caustic);
                }

                // ── Meniscus rim (contact-line bright crescent) ────────────────
                float menArg   = sdf / max(_MeniscusWidth, 0.001);
                float meniscus = exp(-menArg * menArg) * _MeniscusStrength * mask;

                // ── Scene reflection (horizontal mirror) ───────────────────────
                float2 reflUV    = clamp(float2(1.0 - screenUV.x, screenUV.y), 0.001, 0.999);
                float3 reflected = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, reflUV).rgb;

                // ── Composite ─────────────────────────────────────────────────
                float3 dropColor = lerp(refracted, reflected, saturate(fresnel * 0.35));
                dropColor       += caustic * float3(0.92, 0.96, 1.0) * 0.4;

                // Trail uses reduced opacity; main drop uses _Transparency
                float opacity   = isTrail ? (mask * _TrailOpacity) : (mask * _Transparency);
                float3 finalRGB = lerp(scene.rgb, dropColor, opacity);

                finalRGB += spec      * _SpecularColor.rgb;
                finalRGB += meniscus  * _SpecularColor.rgb * (isTrail ? 0.3 : 0.6);

                return half4(finalRGB, 1.0);
            }
            ENDHLSL
        }
    }
}
