Shader "Custom/Morphing/MorphOpticalFlow"
{
    Properties
    {
        _TexA           ("Texture A",              2D)               = "white" {}
        _TexB           ("Texture B",              2D)               = "white" {}
        [Header(Size and Position)]
        [Toggle(_USE_TEXTURE_SIZE)] _UseTextureSize ("Use Actual Texture Size", Float) = 0
        _TexWidthPixels  ("Width (pixels)",        Range(1, 4096))   = 256
        _TexHeightPixels ("Height (pixels)",       Range(1, 4096))   = 256
        _PositionX       ("Start Position X (0=left 1=right)", Range(0,1)) = 0.5
        _PositionY       ("Start Position Y (0=bottom 1=top)", Range(0,1)) = 0.5
        [Header(Motion)]
        [Toggle(_ENABLE_MOTION)] _EnableMotion ("Enable Motion", Float) = 0
        _TargetX         ("Target Position X",     Range(0,1))       = 0.5
        _TargetY         ("Target Position Y",     Range(0,1))       = 0.5
        _MotionDuration  ("Motion Duration (sec)", Range(0.1, 20.0)) = 3.0
        _MotionEase      ("Motion Ease Power",     Range(1.0, 5.0))  = 2.0
        [KeywordEnum(PingPong, Loop, Once)] _MotionMode ("Motion Mode", Float) = 0
        [Header(Time Control)]
        _CycleDuration  ("Cycle Duration (sec)",   Range(0.5, 20.0)) = 4.0
        _HoldDuration   ("Hold Duration (sec)",    Range(0.0, 10.0)) = 1.0
        [Header(Easing)]
        _EasePower      ("Blend Ease Power",       Range(1.0, 5.0))  = 2.0
        [Header(Warp)]
        _WarpStrength   ("Warp Strength",          Range(0, 0.3))    = 0.08
        _BlendSharpness ("Blend Sharpness",        Range(0.01, 0.49))= 0.2
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
            Name "MorphOpticalFlow"

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment frag
            #pragma target 3.5
            #pragma shader_feature_local _USE_TEXTURE_SIZE
            #pragma shader_feature_local _ENABLE_MOTION
            #pragma shader_feature_local _MOTIONMODE_PINGPONG _MOTIONMODE_LOOP _MOTIONMODE_ONCE

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            TEXTURE2D(_TexA); SAMPLER(sampler_TexA);
            TEXTURE2D(_TexB); SAMPLER(sampler_TexB);

            // Must be outside CBUFFER — injected by Unity alongside the sampler
            float4 _TexA_TexelSize;

            CBUFFER_START(UnityPerMaterial)
                float _UseTextureSize;
                float _TexWidthPixels;
                float _TexHeightPixels;
                float _PositionX;
                float _PositionY;
                float _EnableMotion;
                float _TargetX;
                float _TargetY;
                float _MotionDuration;
                float _MotionEase;
                float _MotionMode;
                float _CycleDuration;
                float _HoldDuration;
                float _EasePower;
                float _WarpStrength;
                float _BlendSharpness;
            CBUFFER_END

            // Piecewise ease-in-out: slow→fast→slow across [0,1]
            float EaseInOut(float x, float power)
            {
                float h = 0.5;
                if (x < h)
                    return h * pow(x / h, power);
                else
                    return h + h * (1.0 - pow((1.0 - x) / h, power));
            }

            half4 frag(Varyings IN) : SV_Target
            {
                float2 screenUV = IN.texcoord;

                // ── Scene passthrough ──────────────────────────────────────────
                float4 scene = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, screenUV);

                // ── Texture display size in pixels ─────────────────────────────
                float texW, texH;
                #if defined(_USE_TEXTURE_SIZE)
                    texW = _TexA_TexelSize.z;
                    texH = _TexA_TexelSize.w;
                #else
                    texW = _TexWidthPixels;
                    texH = _TexHeightPixels;
                #endif

                if (texW < 1.0 || texH < 1.0)
                    return half4(scene.rgb, 1.0);

                // ── Animated centre position ───────────────────────────────────
                float cx = _PositionX;
                float cy = _PositionY;

                #if defined(_ENABLE_MOTION)
                {
                    float motionT = 0.0;

                    #if defined(_MOTIONMODE_LOOP)
                        // Continuously travels Start → Target, then jumps back and repeats
                        motionT = fmod(_Time.y, _MotionDuration) / _MotionDuration;
                        motionT = saturate(motionT);

                    #elif defined(_MOTIONMODE_ONCE)
                        // Travels Start → Target once and stops
                        motionT = saturate(_Time.y / _MotionDuration);

                    #else // PingPong (default)
                        // Start → Target → Start → ...
                        float pingPongPeriod = _MotionDuration * 2.0;
                        float localM = fmod(_Time.y, pingPongPeriod);
                        if (localM < _MotionDuration)
                            motionT = localM / _MotionDuration;
                        else
                            motionT = 1.0 - (localM - _MotionDuration) / _MotionDuration;
                        motionT = saturate(motionT);
                    #endif

                    // Apply ease curve to the motion
                    float easedMotion = EaseInOut(motionT, _MotionEase);

                    cx = lerp(_PositionX, _TargetX, easedMotion);
                    cy = lerp(_PositionY, _TargetY, easedMotion);
                }
                #endif

                // ── Compute rect in normalised screen UV ───────────────────────
                float screenW = _ScreenParams.x;
                float screenH = _ScreenParams.y;

                float halfW = (texW * 0.5) / screenW;
                float halfH = (texH * 0.5) / screenH;

                float left   = cx - halfW;
                float right  = cx + halfW;
                float bottom = cy - halfH;
                float top    = cy + halfH;

                // Outside the rect → return scene unchanged
                if (screenUV.x < left  || screenUV.x > right  ||
                    screenUV.y < bottom || screenUV.y > top)
                {
                    return half4(scene.rgb, 1.0);
                }

                // Remap to local texture UV [0,1]
                float2 uv;
                uv.x = (screenUV.x - left)   / (right - left);
                uv.y = (screenUV.y - bottom)  / (top   - bottom);

                // ── Drive blend t over time (ping-pong with hold regions) ──────
                float hold    = _HoldDuration;
                float transit = _CycleDuration * 0.5;
                float period  = transit * 2.0 + hold * 2.0;
                float localT  = fmod(_Time.y, period);

                float tLinear;
                if      (localT < hold)                      tLinear = 0.0;
                else if (localT < hold + transit)            tLinear = (localT - hold) / transit;
                else if (localT < hold * 2.0 + transit)     tLinear = 1.0;
                else                                         tLinear = 1.0 - (localT - hold * 2.0 - transit) / transit;

                float t = EaseInOut(tLinear, _EasePower);

                // ── Sequential two-phase transparency ─────────────────────────
                float tPhase1 = saturate(t * 2.0);
                float tPhase2 = saturate(t * 2.0 - 1.0);

                float s      = _BlendSharpness;
                float alphaB = smoothstep(0.5 - s, 0.5 + s, tPhase1);
                float alphaA = 1.0 - smoothstep(0.5 - s, 0.5 + s, tPhase2);

                // ── Optical flow warp ──────────────────────────────────────────
                float4 rawA  = SAMPLE_TEXTURE2D(_TexA, sampler_TexA, uv);
                float4 rawB  = SAMPLE_TEXTURE2D(_TexB, sampler_TexB, uv);
                float2 flowA = rawA.rg * 2.0 - 1.0;
                float2 flowB = rawB.rg * 2.0 - 1.0;

                float2 uvA = clamp(uv + flowA * (1.0 - alphaA) * _WarpStrength, 0.001, 0.999);
                float2 uvB = clamp(uv - flowB * (1.0 - alphaB) * _WarpStrength, 0.001, 0.999);

                float4 colA = SAMPLE_TEXTURE2D(_TexA, sampler_TexA, uvA);
                float4 colB = SAMPLE_TEXTURE2D(_TexB, sampler_TexB, uvB);

                // ── Alpha composite (Porter-Duff "B over A") ───────────────────
                float texAlphaA  = colA.a * alphaA;
                float texAlphaB  = colB.a * alphaB;
                float morphAlpha = texAlphaB + texAlphaA * (1.0 - texAlphaB);

                // ── RGB composite ──────────────────────────────────────────────
                float3 morphRGB = (colA.rgb * texAlphaA + colB.rgb * texAlphaB * (1.0 - texAlphaA))
                                  / max(morphAlpha, 0.0001);

                // ── Composite morph over scene ─────────────────────────────────
                float3 finalRGB = morphRGB * morphAlpha + scene.rgb * (1.0 - morphAlpha);

                return half4(finalRGB, 1.0);
            }
            ENDHLSL
        }
    }
}
