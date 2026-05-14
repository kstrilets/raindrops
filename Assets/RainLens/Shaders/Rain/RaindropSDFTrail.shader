Shader "Custom/Rain/RaindropSDFTrail"
{
    // ── Overview ──────────────────────────────────────────────────────────────
    //
    // A raindrop sliding down a window rendered in a single fullscreen pass.
    //
    // TWO separate SDFs share the pass:
    //
    //   TRAIL — a narrow vertical ellipse anchored at (_PositionX, _PositionY).
    //           Its TOP stays fixed.  Its BOTTOM follows the drop's top edge,
    //           so the trail grows longer as the drop descends.
    //           Independent wettability seed → different ragged-edge outline.
    //
    //   DROP  — a round-ish drop whose centre descends from the anchor point.
    //           Gravity deformation (flatten at bottom / sharpen top) is applied
    //           in drop-local space.  Composited ON TOP of the trail so the
    //           join looks seamless.
    //
    // Both shapes are driven by a single animated value sagT ∈ [0,1]:
    //
    //   dropCenterY  = _PositionY  −  sagT * _SagMaxOffset   (descends)
    //   trailHalfH   grows to fill the gap between anchor and drop top edge
    //   g            = lerp(_SagMin, _SagMax, sagT)           (deforms drop)
    //
    // As sagT rises 0 → 1:
    //   • Drop centre moves downward by _SagMaxOffset screen fractions.
    //   • Trail ellipse stretches to bridge the growing gap.
    //   • Drop shape simultaneously deforms (flatten bottom / sharpen top).
    //
    // Animation timeline per cycle:
    //   [0 … SagRiseDuration]      sagT rises 0→1  (ease-in)
    //   [SagRiseDuration … period] hold at sagT=1 for SagHoldDuration seconds
    //   → instant reset to sagT=0, repeat
    //
    // Use _PhaseOffset to stagger multiple drop materials.

    Properties
    {
        [Header(Anchor Position)]
        _PositionX          ("Column X  (0=left 1=right)",             Range(0,1))         = 0.5
        _PositionY          ("Anchor Y  (trail top, 0=bottom 1=top)",  Range(0,1))         = 0.75

        [Header(Sag Animation)]
        _SagMaxOffset       ("Max Drop Descent (fraction of screen)",   Range(0.0, 0.6))    = 0.28
        _SagMin             ("Gravity Sag at Rest",                     Range(0.01, 0.4))   = 0.04
        _SagMax             ("Gravity Sag at Peak",                     Range(0.05, 0.6))   = 0.36
        _SagRiseDuration    ("Sag Rise Duration (sec)",                 Range(0.2, 15.0))   = 3.5
        _SagHoldDuration    ("Hold at Peak (sec)",                      Range(0.0, 8.0))    = 0.6
        _SagEase            ("Rise Ease Power (1=linear)",              Range(1.0, 5.0))    = 2.2
        _PhaseOffset        ("Phase Offset (sec, stagger drops)",       Float)              = 0.0

        [Header(Drop Shape)]
        _DropRadius         ("Drop Radius (pixels)",                    Range(8, 512))      = 72.0
        _DropAspect         ("Drop Width / Height ratio",               Range(0.3, 1.6))    = 0.82

        [Header(Drop Wettability)]
        _WettabilityStrength("Drop Irregularity Strength",              Range(0.0, 0.55))   = 0.22
        _WettabilityScale   ("Drop Irregularity Frequency",             Range(0.5, 8.0))    = 2.8
        _WettabilitySeed    ("Drop Shape Seed",                         Float)              = 0.0

        [Header(Trail Shape)]
        _TrailWidthRatio    ("Trail Width (fraction of drop radius)",   Range(0.05, 0.8))   = 0.28

        [Header(Trail Wettability independent shape)]
        _TrailWettabilityStrength("Trail Irregularity Strength",        Range(0.0, 0.75))   = 0.45
        _TrailWettabilityScale   ("Trail Irregularity Frequency",       Range(0.5, 12.0))   = 4.8
        _TrailWettabilitySeed    ("Trail Shape Seed",                   Float)              = 47.3

        [Header(Trail Optics)]
        _TrailOpacity       ("Trail Opacity",                           Range(0.0, 1.0))    = 0.50
        _TrailIOR           ("Trail IOR (thin film < 1.333)",           Range(1.0, 1.5))    = 1.16
        _TrailLensThickness ("Trail Lens Thickness",                    Range(0.0, 0.5))    = 0.18
        _TrailSpecularScale ("Trail Specular Scale (0=none)",           Range(0.0, 1.0))    = 0.28

        [Header(Drop Optics)]
        _IOR                ("Drop IOR (water = 1.333)",                Range(1.0, 1.8))    = 1.333
        _LensThickness      ("Drop Lens Thickness",                     Range(0.0, 1.0))    = 0.55
        _ChromaticAberration("Chromatic Aberration",                    Range(0.0, 0.025))  = 0.005
        _DropTint           ("Water Tint (A = strength)",               Color)              = (0.82, 0.93, 1.0, 0.07)
        _Transparency       ("Drop Transparency",                       Range(0.0, 1.0))    = 0.92

        [Header(Lighting)]
        _LightDirX          ("Light Dir X",                             Range(-1.0, 1.0))   = -0.35
        _LightDirY          ("Light Dir Y",                             Range(-1.0, 1.0))   =  0.65
        _FresnelStrength    ("Fresnel Rim Strength",                    Range(0.0, 2.0))    = 0.85
        _FresnelPower       ("Fresnel Power",                           Range(1.0, 10.0))   = 3.5
        _SpecularStrength   ("Specular Strength",                       Range(0.0, 6.0))    = 2.5
        _SpecularSharpness  ("Specular Sharpness",                      Range(8, 512))      = 128.0
        _SpecularColor      ("Specular / Rim Color",                    Color)              = (1.0, 1.0, 1.0, 1.0)

        [Header(Caustic and Meniscus)]
        _CausticStrength    ("Caustic Ring Strength",                   Range(0.0, 3.0))    = 0.65
        _CausticRadius      ("Caustic Ring Radius",                     Range(0.3, 0.98))   = 0.72
        _CausticWidth       ("Caustic Ring Width",                      Range(0.01, 0.25))  = 0.07
        _MeniscusStrength   ("Meniscus Rim Brightness",                 Range(0.0, 3.0))    = 0.50
        _MeniscusWidth      ("Meniscus Width",                          Range(0.002, 0.1))  = 0.02
        _EdgeSoftness       ("Edge Softness (pixels)",                  Range(0.3, 4.0))    = 1.5
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
                float  _SagMaxOffset;
                float  _SagMin;
                float  _SagMax;
                float  _SagRiseDuration;
                float  _SagHoldDuration;
                float  _SagEase;
                float  _PhaseOffset;
                float  _DropRadius;
                float  _DropAspect;
                float  _WettabilityStrength;
                float  _WettabilityScale;
                float  _WettabilitySeed;
                float  _TrailWidthRatio;
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

            // ── Noise helpers ──────────────────────────────────────────────────

            float hash1(float2 p)
            {
                return frac(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
            }

            float valueNoise(float2 p)
            {
                float2 i = floor(p);
                float2 f = frac(p);
                float2 u = f * f * (3.0 - 2.0 * f);
                return lerp(lerp(hash1(i),               hash1(i + float2(1,0)), u.x),
                            lerp(hash1(i + float2(0,1)), hash1(i + float2(1,1)), u.x), u.y);
            }

            // 3-octave FBM domain warp — models contact-angle hysteresis.
            float2 WarpDomain(float2 p, float scale, float seed)
            {
                float2 s = seed * float2(1.0, 1.618);

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

            // Ease-in: slow start → fast end (mimics a drop clinging then releasing).
            float EaseIn(float x, float power)
            {
                return pow(saturate(x), power);
            }

            // ── Thin-lens refraction + lighting ───────────────────────────────
            //
            // shapeP   : SDF-local coords, unit-circle edge = 1.
            // aspect   : pixel-space X/Y radius ratio (converts gradient to UV).
            // radiusPx : Y radius in pixels.
            void ComputeOptics(
                float2 screenUV,
                float2 shapeP,
                float  aspect,
                float  radiusPx,
                float  mask,
                float  ior,
                float  lensThickness,
                float  specStrength,
                float  specSharpness,
                out float3 refracted,
                out float  fresnel,
                out float  spec,
                out float  caustic)
            {
                float  rSq   = dot(shapeP, shapeP);
                float  r     = sqrt(rSq);
                float  h     = saturate(1.0 - rSq);
                float2 gradH = -2.0 * shapeP;

                float2 screenGrad = float2(gradH.x / max(aspect, 0.01), gradH.y)
                                  / max(radiusPx, 1.0);

                float  refrScale = h * lensThickness * (ior - 1.0) * 0.07;
                float2 refrOff   = screenGrad * refrScale;

                float2 uvR = clamp(screenUV + refrOff * (1.0 + _ChromaticAberration), 0.001, 0.999);
                float2 uvG = clamp(screenUV + refrOff,                                0.001, 0.999);
                float2 uvB = clamp(screenUV + refrOff * (1.0 - _ChromaticAberration), 0.001, 0.999);

                refracted.r = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uvR).r;
                refracted.g = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uvG).g;
                refracted.b = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uvB).b;
                refracted   = lerp(refracted, _DropTint.rgb, _DropTint.a * h);

                float3 N = normalize(float3(
                    gradH.x / max(aspect, 0.01),
                    gradH.y,
                    1.0 / max(lensThickness, 0.01)
                ));

                float3 V = float3(0, 0, 1);
                fresnel  = pow(1.0 - saturate(dot(N, V)), _FresnelPower)
                         * _FresnelStrength * mask;

                float3 L = normalize(float3(_LightDirX, _LightDirY, 0.7));
                float3 H = normalize(L + V);
                spec     = pow(saturate(dot(N, H)), max(specSharpness, 1.0))
                         * specStrength * mask;

                float ca = (r - _CausticRadius) / max(_CausticWidth, 0.001);
                caustic  = exp(-ca * ca) * _CausticStrength * mask;
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

                // ── Sag animation ──────────────────────────────────────────────
                //
                // sagT ∈ [0,1]:  0 = drop at anchor, trail is zero length.
                //                1 = drop at max descent, trail at full length.
                float safeTime = fmod(_Time.y + _PhaseOffset, 3600.0);
                float period   = _SagRiseDuration + _SagHoldDuration;
                float localT   = fmod(safeTime, max(period, 0.001));
                float sagT     = EaseIn(saturate(localT / max(_SagRiseDuration, 0.001)),
                                        _SagEase);
                float g        = lerp(_SagMin, _SagMax, sagT);

                // ── Derived positions ──────────────────────────────────────────
                //
                // UV convention: y=1 is TOP of screen, y=0 is BOTTOM.
                // Subtracting moves the centre downward on screen.
                float dropCenterY = _PositionY - sagT * _SagMaxOffset;
                float dropCenterX = _PositionX;

                // The top of the drop body in UV — one radius above the centre.
                // Trail bottom snaps to this point so there is no gap.
                float dropTopEdgeY = dropCenterY + _DropRadius / screenH;

                // Trail spans from _PositionY (fixed top) to dropTopEdgeY (moving bottom).
                float trailTopY    = _PositionY;
                float trailBotY    = min(dropTopEdgeY, trailTopY); // clamp: never inverts
                float trailMidY    = (trailTopY + trailBotY) * 0.5;

                float trailHalfHPx = max((trailTopY - trailBotY) * screenH * 0.5, 0.5);
                float trailHalfWPx = max(_DropRadius * _TrailWidthRatio, 1.0);

                // ── ① TRAIL SDF ────────────────────────────────────────────────
                //
                // Local coord normalised so the unwarped ellipse edge = 1.
                float2 trailDelta = (screenUV - float2(_PositionX, trailMidY))
                                  * float2(screenW, screenH);
                float2 trailP     = float2(trailDelta.x / trailHalfWPx,
                                           trailDelta.y / trailHalfHPx);

                float  rTrail    = length(trailP);
                float  edgeWT    = exp(-((rTrail - 1.0) * (rTrail - 1.0)) / 0.09);
                float2 trailWarp = WarpDomain(trailP,
                                              _TrailWettabilityScale,
                                              _TrailWettabilitySeed)
                                 * _TrailWettabilityStrength * edgeWT;

                float trailSDF  = length(trailP + trailWarp) - 1.0;
                float trailMask = 1.0 - smoothstep(-aaW, aaW, trailSDF);

                // Fade trail in as it gains height (avoids a pop at sagT=0)
                trailMask *= saturate(trailHalfHPx / max(_DropRadius * 0.15, 1.0));

                // ── ② DROP SDF ─────────────────────────────────────────────────
                //
                // Drop-local coord: (0,0) at centre, |p|≈1 at unwarped edge.
                float2 dropDelta = (screenUV - float2(dropCenterX, dropCenterY))
                                 * float2(screenW, screenH);
                float2 dropP     = dropDelta / max(_DropRadius, 1.0);
                dropP.x         /= max(_DropAspect, 0.01);

                // Gravity deformation — downward-opening parabola:
                //   Flattens the bottom, sharpens the top, sags the centre down.
                float2 dropShapeP;
                dropShapeP.x = dropP.x;
                dropShapeP.y = dropP.y * (1.0 - g * dropP.y) + g * 0.15;

                float  rDrop   = length(dropShapeP);
                float  edgeWD  = exp(-((rDrop - 1.0) * (rDrop - 1.0)) / 0.09);
                float2 dropWarp = WarpDomain(dropShapeP,
                                             _WettabilityScale,
                                             _WettabilitySeed)
                                * _WettabilityStrength * edgeWD;

                float dropSDF  = length(dropShapeP + dropWarp) - 1.0;
                float dropMask = 1.0 - smoothstep(-aaW, aaW, dropSDF);

                // Early-out: pixel belongs to neither shape
                if (trailMask < 0.001 && dropMask < 0.001)
                    return half4(scene.rgb, 1.0);

                // ── Trail optics ───────────────────────────────────────────────
                float  trailAspect = trailHalfWPx / max(trailHalfHPx, 1.0);
                float3 trailRefracted;
                float  trailFresnel, trailSpec, trailCaustic;
                ComputeOptics(screenUV, trailP, trailAspect, trailHalfHPx,
                              trailMask,
                              _TrailIOR, _TrailLensThickness,
                              _SpecularStrength * _TrailSpecularScale, _SpecularSharpness,
                              trailRefracted, trailFresnel, trailSpec, trailCaustic);

                // ── Drop optics ────────────────────────────────────────────────
                float3 dropRefracted;
                float  dropFresnel, dropSpec, dropCaustic;
                ComputeOptics(screenUV, dropShapeP, _DropAspect, _DropRadius,
                              dropMask,
                              _IOR, _LensThickness,
                              _SpecularStrength, _SpecularSharpness,
                              dropRefracted, dropFresnel, dropSpec, dropCaustic);

                // ── Approximate scene reflection (horizontal mirror) ────────────
                float2 reflUV    = clamp(float2(1.0 - screenUV.x, screenUV.y), 0.001, 0.999);
                float3 reflected = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, reflUV).rgb;

                // ── Composite: trail first, drop on top ────────────────────────
                float3 finalRGB = scene.rgb;

                // Trail layer
                float3 trailColor = lerp(trailRefracted, reflected, saturate(trailFresnel * 0.25));
                trailColor       += trailCaustic * float3(0.92, 0.96, 1.0) * 0.3;
                finalRGB          = lerp(finalRGB, trailColor, trailMask * _TrailOpacity);
                finalRGB         += trailSpec * _SpecularColor.rgb;

                float trailMenArg = trailSDF / max(_MeniscusWidth, 0.001);
                finalRGB += exp(-trailMenArg * trailMenArg)
                          * _MeniscusStrength * trailMask * _SpecularColor.rgb * 0.28;

                // Drop layer (over trail — covers the join seam)
                float3 dropColor = lerp(dropRefracted, reflected, saturate(dropFresnel * 0.35));
                dropColor       += dropCaustic * float3(0.92, 0.96, 1.0) * 0.4;
                finalRGB         = lerp(finalRGB, dropColor, dropMask * _Transparency);
                finalRGB        += dropSpec * _SpecularColor.rgb;

                float dropMenArg = dropSDF / max(_MeniscusWidth, 0.001);
                finalRGB += exp(-dropMenArg * dropMenArg)
                          * _MeniscusStrength * dropMask * _SpecularColor.rgb * 0.60;

                return half4(finalRGB, 1.0);
            }
            ENDHLSL
        }
    }
}
