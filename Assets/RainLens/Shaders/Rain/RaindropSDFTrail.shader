Shader "Custom/Rain/RaindropSDFTrail"
{
    // ── Overview ──────────────────────────────────────────────────────────────
    //
    // A single raindrop sliding DOWN a window, leaving a residual trail ABOVE it.
    //
    // The drop position is animated entirely inside the shader — no C# needed.
    // Drive _PositionX from C# only if you want horizontal placement; everything
    // else is time-driven.
    //
    // TWO physically distinct parts are rendered in one pass:
    //
    //   MAIN DROP  — the current falling body.
    //                Round-ish, full opacity, strong refraction, sharp specular.
    //
    //   TRAIL BLOB — the thin residual film left behind ABOVE the drop.
    //                Identified via the gravity-quadratic fold (see below).
    //                Independently shaped: different wettability seed → different
    //                contact-line outline. Narrower aspect, lower IOR (thin film),
    //                reduced opacity, dimmer specular.
    //
    // How the trail appears above:
    //   The gravity quadratic  shapeP.y = py·(1 − g·py) + g·0.15
    //   has its parabola vertex at py = +1/(2g) — i.e. ABOVE the drop centre
    //   in drop-local space.  Pixels above that threshold fold back through the
    //   SDF unit circle, producing a phantom blob above the main drop body.
    //   Because the branch test is done on the RAW py (before the quadratic),
    //   each branch receives independent wettability parameters → genuinely
    //   different shapes.
    //
    // Animation:
    //   The drop loops from _SlideTopY (near top of screen) down to _SlideBottomY.
    //   A configurable ease and hold-at-bottom pause make the motion feel weighty.
    //   _SlidePhaseOffset shifts the timing so multiple materials don't synchronise.

    Properties
    {
        [Header(Animation)]
        _SlideTopY          ("Slide Start Y  (top,    0–1)",      Range(0,1))         = 0.85
        _SlideBottomY       ("Slide End Y    (bottom, 0–1)",      Range(0,1))         = 0.12
        _SlideDuration      ("Slide Duration (sec)",               Range(0.3, 20.0))   = 4.0
        _SlideHoldBottom    ("Hold at Bottom (sec)",               Range(0.0, 10.0))   = 1.2
        _SlideEase          ("Slide Ease Power (1=linear)",        Range(1.0, 5.0))    = 2.0
        _SlidePhaseOffset   ("Phase Offset (sec, stagger drops)",  Float)              = 0.0
        _PositionX          ("Column X  (0=left 1=right)",         Range(0,1))         = 0.5

        [Header(Drop Shape)]
        _DropRadius         ("Drop Radius (pixels)",               Range(8, 512))      = 80.0
        _DropAspect         ("Drop Width / Height ratio",          Range(0.3, 1.6))    = 0.82
        _GravityFlattening  ("Gravity Sag  (controls trail distance)", Range(0.01, 0.6)) = 0.18

        [Header(Drop Wettability)]
        _WettabilityStrength("Drop Irregularity Strength",         Range(0.0, 0.55))   = 0.22
        _WettabilityScale   ("Drop Irregularity Frequency",        Range(0.5, 8.0))    = 2.8
        _WettabilitySeed    ("Drop Shape Seed",                    Float)              = 0.0

        [Header(Trail Blob Shape)]
        // Trail is narrow and vertically elongated — a thin smear of water film.
        _TrailAspect        ("Trail Width / Height ratio",         Range(0.1, 1.2))    = 0.35
        _TrailStretch       ("Trail Y Stretch (elongation)",       Range(0.5, 5.0))    = 1.8

        [Header(Trail Wettability - independent shape)]
        _TrailWettabilityStrength("Trail Irregularity Strength",   Range(0.0, 0.75))   = 0.45
        _TrailWettabilityScale   ("Trail Irregularity Frequency",  Range(0.5, 12.0))   = 4.8
        _TrailWettabilitySeed    ("Trail Shape Seed",              Float)              = 47.3

        [Header(Trail Optics)]
        _TrailOpacity       ("Trail Opacity",                      Range(0.0, 1.0))    = 0.52
        _TrailIOR           ("Trail IOR  (thin film < 1.333)",     Range(1.0, 1.5))    = 1.16
        _TrailLensThickness ("Trail Lens Thickness",               Range(0.0, 0.5))    = 0.18
        _TrailSpecularScale ("Trail Specular Scale  (0=none)",     Range(0.0, 1.0))    = 0.28

        [Header(Drop Optics)]
        _IOR                ("Drop IOR  (water = 1.333)",          Range(1.0, 1.8))    = 1.333
        _LensThickness      ("Drop Lens Thickness",                Range(0.0, 1.0))    = 0.55
        _ChromaticAberration("Chromatic Aberration",               Range(0.0, 0.025))  = 0.005
        _DropTint           ("Water Tint  (A = strength)",         Color)              = (0.82, 0.93, 1.0, 0.07)
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
                float  _SlideTopY;
                float  _SlideBottomY;
                float  _SlideDuration;
                float  _SlideHoldBottom;
                float  _SlideEase;
                float  _SlidePhaseOffset;
                float  _PositionX;
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

            // ── Noise / FBM helpers ────────────────────────────────────────────

            float hash1(float2 p)
            {
                return frac(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
            }

            float valueNoise(float2 p)
            {
                float2 i = floor(p);
                float2 f = frac(p);
                float2 u = f * f * (3.0 - 2.0 * f);
                return lerp(lerp(hash1(i),                hash1(i + float2(1,0)), u.x),
                            lerp(hash1(i + float2(0,1)),  hash1(i + float2(1,1)), u.x), u.y);
            }

            // 3-octave FBM domain warp — models contact-angle hysteresis.
            // Returns displacement in drop-local normalised space.
            float2 WarpDomain(float2 p, float scale, float seed)
            {
                float2 s = seed * float2(1.0, 1.618);

                // Octave 1 — large pinning blobs
                float2 p1 = p * scale + s;
                float2 w  = float2(valueNoise(p1),
                                   valueNoise(p1 + float2(5.2, 1.3))) * 2.0 - 1.0;

                // Octave 2 — medium roughness
                float2 p2 = p * (scale * 2.1) + s + float2(3.7, 8.1);
                w        += 0.5 * (float2(valueNoise(p2),
                                          valueNoise(p2 + float2(5.2, 1.3))) * 2.0 - 1.0);

                // Octave 3 — fine micro-detail
                float2 p3 = p * (scale * 4.3) + s + float2(6.2, 2.9);
                w        += 0.25 * (float2(valueNoise(p3),
                                           valueNoise(p3 + float2(5.2, 1.3))) * 2.0 - 1.0);

                return w / 1.75;
            }

            // ── Easing ─────────────────────────────────────────────────────────
            // Ease-in only: slow start → fast end (drop accelerates under gravity).
            float EaseIn(float x, float power)
            {
                return pow(saturate(x), power);
            }

            // ── Optics sub-routine ─────────────────────────────────────────────
            // Shared by main drop and trail blob; caller passes per-branch params.
            void ComputeOptics(
                float2 screenUV,
                float2 shapeP,
                float  branchAspect,
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
                // Paraboloid height field: h = 1 − r²
                float  rSq   = dot(shapeP, shapeP);
                float  r     = sqrt(rSq);
                float  h     = saturate(1.0 - rSq);
                float2 gradH = -2.0 * shapeP;

                // Gradient in screen-UV space
                float2 screenGrad = float2(gradH.x / max(branchAspect, 0.01), gradH.y)
                                  / max(dropRadius, 1.0);

                // Thin-lens refraction with chromatic aberration
                float  refrScale = h * lensThickness * (ior - 1.0) * 0.07;
                float2 refrOff   = screenGrad * refrScale;

                float2 uvR = clamp(screenUV + refrOff * (1.0 + _ChromaticAberration), 0.001, 0.999);
                float2 uvG = clamp(screenUV + refrOff,                                0.001, 0.999);
                float2 uvB = clamp(screenUV + refrOff * (1.0 - _ChromaticAberration), 0.001, 0.999);

                refracted.r = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uvR).r;
                refracted.g = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uvG).g;
                refracted.b = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uvB).b;
                refracted   = lerp(refracted, _DropTint.rgb, _DropTint.a * h);

                // Surface normal from paraboloid
                N = normalize(float3(
                    gradH.x / max(branchAspect, 0.01),
                    gradH.y,
                    1.0 / max(lensThickness, 0.01)
                ));

                float3 V    = float3(0, 0, 1);
                float  cosT = saturate(dot(N, V));
                fresnel     = pow(1.0 - cosT, _FresnelPower) * _FresnelStrength * mask;

                float3 L    = normalize(float3(_LightDirX, _LightDirY, 0.7));
                float3 H    = normalize(L + V);
                spec        = pow(saturate(dot(N, H)), max(specSharpness, 1.0))
                            * specStrength * mask;

                // Caustic ring
                float ca = (r - _CausticRadius) / max(_CausticWidth, 0.001);
                caustic   = exp(-ca * ca) * _CausticStrength * mask;
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

                // ── Animate drop Y position ────────────────────────────────────
                //
                // The drop loops from SlideTopY (high on screen) down to SlideBottomY,
                // pauses briefly at the bottom, then jumps back to the top.
                //
                // Timeline per cycle:
                //   [0 .. SlideDuration]                → active slide  (ease-in)
                //   [SlideDuration .. period]            → hold at bottom
                //
                // EaseIn gives the drop a sense of gravitational acceleration.
                float safeTime  = fmod(_Time.y + _SlidePhaseOffset, 3600.0);
                float period    = _SlideDuration + _SlideHoldBottom;
                float localT    = fmod(safeTime, period);
                float slideT    = EaseIn(saturate(localT / max(_SlideDuration, 0.001)),
                                         _SlideEase);

                // posY moves from top → bottom as slideT goes 0 → 1
                float posY      = lerp(_SlideTopY, _SlideBottomY, slideT);

                // ── Drop-local normalised coordinate ───���───────────────────────
                // p = (0,0) at drop centre; |p| ≈ 1 at unperturbed edge.
                float2 delta = (screenUV - float2(_PositionX, posY))
                             * float2(screenW, screenH);
                float2 p     = delta / max(_DropRadius, 1.0);
                p.x         /= max(_DropAspect, 0.01);

                // ── Branch discriminant (done on RAW p.y) ──────────────────────
                //
                // Gravity quadratic used below:
                //   shapeP.y = py·(1 − g·py) + g·0.15
                //
                // This is a downward-opening parabola with vertex at py = +1/(2g).
                // Pixels ABOVE that vertex (py > vertexY) fold back through the SDF
                // and appear as the trail blob above the main drop.
                // Pixels BELOW the vertex (py < vertexY) are the main drop body.
                //
                // The branch is identified here, before the quadratic, so the two
                // parts can receive completely independent wettability parameters.
                float vertexY = 1.0 / (2.0 * max(_GravityFlattening, 0.001));
                bool  isTrail = (p.y > vertexY);

                // ── Gravity quadratic ──────────────────────────────────────────
                // shapeP.y = py·(1 − g·py) + g·0.15
                //
                // Effect on the main drop body (py < vertexY):
                //   py < 0 (below centre): (1−g·py) > 1 → |shapeP.y| compressed
                //     → SDF boundary pushed DOWN in screen → wider/flatter bottom ✓
                //   py > 0 (above centre): (1−g·py) < 1 → |shapeP.y| expanded
                //     → SDF boundary pushed UP → narrower, pointed top ✓
                //
                // The +g·0.15 bias shifts the mass centre slightly downward,
                // making the whole drop appear to sag under gravity.
                float2 shapeP;
                shapeP.x = p.x;
                shapeP.y = p.y * (1.0 - _GravityFlattening * p.y)
                         + _GravityFlattening * 0.15;

                // ── Per-branch aspect and stretch ──────────────────────────────
                // The trail is rescaled AFTER the quadratic:
                //   • narrower X  (smaller pixel footprint left/right)
                //   • compressed Y (stretches the SDF circle vertically on screen)
                // This is independent of where the fold falls.
                float2 branchP;
                if (isTrail)
                {
                    branchP.x = shapeP.x / max(_TrailAspect,   0.01) * max(_DropAspect, 0.01);
                    branchP.y = shapeP.y / max(_TrailStretch,  0.01);
                }
                else
                {
                    branchP = shapeP;
                }

                // ── Wettability domain warp ────────────────────────────────────
                // Concentrated at the contact line (edgeWeight = Gaussian on |r|−1).
                // Trail and main drop use DIFFERENT seeds → different random outlines.
                float  rBranch = length(branchP);
                float  edgeW   = exp(-((rBranch - 1.0) * (rBranch - 1.0)) / 0.09);

                float2 warpOff;
                if (isTrail)
                    warpOff = WarpDomain(branchP, _TrailWettabilityScale,   _TrailWettabilitySeed)
                            * _TrailWettabilityStrength * edgeW;
                else
                    warpOff = WarpDomain(branchP, _WettabilityScale, _WettabilitySeed)
                            * _WettabilityStrength * edgeW;

                float2 warpedP = branchP + warpOff;

                // ── SDF mask ───────────────────────────────────────────────────
                float pixSz = 1.0 / max(_DropRadius, 1.0);
                float aaW   = _EdgeSoftness * pixSz;
                float sdf   = length(warpedP) - 1.0;
                float mask  = 1.0 - smoothstep(-aaW, aaW, sdf);

                if (mask < 0.001)
                    return half4(scene.rgb, 1.0);

                // ── Optics ─────────────────────────────────────────────────────
                float3 refracted, N;
                float  fresnel, spec, caustic;

                if (isTrail)
                {
                    ComputeOptics(
                        screenUV, branchP,
                        _TrailAspect,  _DropRadius, mask,
                        _TrailIOR,     _TrailLensThickness,
                        _SpecularStrength * _TrailSpecularScale, _SpecularSharpness,
                        refracted, N, fresnel, spec, caustic);
                }
                else
                {
                    ComputeOptics(
                        screenUV, branchP,
                        _DropAspect,   _DropRadius, mask,
                        _IOR,          _LensThickness,
                        _SpecularStrength, _SpecularSharpness,
                        refracted, N, fresnel, spec, caustic);
                }

                // ── Meniscus rim ───────────────────────────────────────────────
                float menArg   = sdf / max(_MeniscusWidth, 0.001);
                float meniscus = exp(-menArg * menArg) * _MeniscusStrength * mask;

                // ── Approximate scene reflection (horizontal mirror) ────────────
                float2 reflUV    = clamp(float2(1.0 - screenUV.x, screenUV.y), 0.001, 0.999);
                float3 reflected = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, reflUV).rgb;

                // ── Composite ─────────────────────────────────────────────────
                float3 V2       = float3(0, 0, 1);
                float3 dropColor = lerp(refracted, reflected, saturate(fresnel * 0.35));
                dropColor       += caustic * float3(0.92, 0.96, 1.0) * 0.4;

                float  opacity   = isTrail ? (mask * _TrailOpacity) : (mask * _Transparency);
                float3 finalRGB  = lerp(scene.rgb, dropColor, opacity);

                finalRGB += spec      * _SpecularColor.rgb;
                finalRGB += meniscus  * _SpecularColor.rgb * (isTrail ? 0.28 : 0.60);

                return half4(finalRGB, 1.0);
            }
            ENDHLSL
        }
    }
}
