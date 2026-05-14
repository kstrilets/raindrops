Shader "Custom/Morphing/MorphOpticalFlow"
{
    Properties
    {
        [Header(Spritesheet)]
        _Spritesheet     ("Spritesheet",                      2D)               = "white" {}
        _Cols            ("Columns",                          Range(1, 32))     = 4
        _Rows            ("Rows",                             Range(1, 32))     = 2

        [Header(Size and Position)]
        [Toggle(_USE_TEXTURE_SIZE)] _UseTextureSize ("Use Actual Tile Size", Float) = 0
        _TexWidthPixels  ("Tile Width  (pixels)",             Range(1, 4096))   = 256
        _TexHeightPixels ("Tile Height (pixels)",             Range(1, 4096))   = 256
        _PositionX       ("Start Position X (0=left 1=right)", Range(0,1))     = 0.5
        _PositionY       ("Start Position Y (0=bottom 1=top)", Range(0,1))     = 0.5

        [Header(Motion)]
        [Toggle(_ENABLE_MOTION)] _EnableMotion  ("Enable Motion",        Float)            = 0
        _TargetX         ("Target Position X",                Range(0,1))       = 0.5
        _TargetY         ("Target Position Y",                Range(0,1))       = 0.5
        _MotionDuration  ("Motion Duration (sec)",            Range(0.1, 20.0)) = 3.0
        _MotionEase      ("Motion Ease Power",                Range(1.0, 5.0))  = 2.0
        [KeywordEnum(PingPong, Loop, Once)] _MotionMode ("Motion Mode",  Float) = 0
        // Set from C#: material.SetFloat("_StartTime", Time.time) when Motion Mode = Once
        _StartTime       ("Start Time (set from C#)",         Float)            = 0.0

        [Header(Time Control)]
        _CycleDuration   ("Morph Duration (sec)",             Range(0.1, 20.0)) = 2.0
        _HoldDuration    ("Hold Duration (sec)",              Range(0.0, 10.0)) = 1.0

        [Header(Easing)]
        _EasePower       ("Blend Ease Power (1=linear 5=strong)", Range(1.0, 5.0)) = 2.0

        [Header(Warp)]
        _WarpStrength    ("Warp Strength",                    Range(0, 0.3))    = 0.08
        _BlendSharpness  ("Blend Sharpness",                  Range(0.01, 0.49))= 0.2
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

            TEXTURE2D(_Spritesheet); SAMPLER(sampler_Spritesheet);

            // Must be OUTSIDE CBUFFER — Unity injects it automatically.
            // float4(1/texW, 1/texH, texW, texH) — full spritesheet dimensions.
            float4 _Spritesheet_TexelSize;

            CBUFFER_START(UnityPerMaterial)
                // _UseTextureSize, _EnableMotion, _MotionMode are keyword-only — NOT in CBUFFER.
                float _Cols;
                float _Rows;
                float _TexWidthPixels;
                float _TexHeightPixels;
                float _PositionX;
                float _PositionY;
                float _TargetX;
                float _TargetY;
                float _MotionDuration;
                float _MotionEase;
                float _StartTime;
                float _CycleDuration;
                float _HoldDuration;
                float _EasePower;
                float _WarpStrength;
                float _BlendSharpness;
            CBUFFER_END

            // Ease-in-out curve. Input is saturated first to prevent NaN from pow(negative).
            float EaseInOut(float x, float power)
            {
                x = saturate(x);
                float h = 0.5;
                if (x < h)
                    return h * pow(x / h, power);
                else
                    return h + h * (1.0 - pow((1.0 - x) / h, power));
            }

            // Convert a linear frame index into spritesheet UV rect (offset + scale).
            // Spritesheet layout: row 0 is TOP, columns go left→right.
            // Frame 0 = row 0 col 0, frame 1 = row 0 col 1, ...
            // frame cols = row 1 col 0, etc.
            //
            // Returns float4(offsetX, offsetY, scaleX, scaleY) in UV space.
            float4 FrameRect(float frameIndex, float cols, float rows)
            {
                float col = fmod(frameIndex, cols);
                float row = floor(frameIndex / cols);

                float scaleX  = 1.0 / cols;
                float scaleY  = 1.0 / rows;
                float offsetX = col  * scaleX;
                float offsetY = row  * scaleY;

                return float4(offsetX, offsetY, scaleX, scaleY);
            }

            // Sample the spritesheet at local tile UV [0,1] for a given frame.
            float4 SampleFrame(float2 tileUV, float4 rect)
            {
                // rect.xy = UV offset, rect.zw = UV scale
                // Clamp tileUV inside the cell with a half-texel margin to prevent
                // bleeding from adjacent frames.
                float2 cellUV = clamp(tileUV, 0.001, 0.999);
                float2 uv     = rect.xy + cellUV * rect.zw;
                return SAMPLE_TEXTURE2D(_Spritesheet, sampler_Spritesheet, uv);
            }

            half4 frag(Varyings IN) : SV_Target
            {
                float2 screenUV = IN.texcoord;

                // ── Scene passthrough ──────────────────────────────────────────
                float4 scene = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, screenUV);

                // ── Guard: _ScreenParams = (1,1) in some early URP blit passes ─
                float screenW = _ScreenParams.x;
                float screenH = _ScreenParams.y;
                if (screenW < 2.0 || screenH < 2.0)
                    return half4(scene.rgb, 1.0);

                // ── Tile display size in pixels ────────────────────────────────
                // _USE_TEXTURE_SIZE: derive one tile's pixel size from the sheet.
                float texW, texH;
                #if defined(_USE_TEXTURE_SIZE)
                    // Full sheet size / grid → single tile size
                    texW = _Spritesheet_TexelSize.z / max(_Cols, 1.0);
                    texH = _Spritesheet_TexelSize.w / max(_Rows, 1.0);
                #else
                    texW = _TexWidthPixels;
                    texH = _TexHeightPixels;
                #endif

                if (texW < 1.0 || texH < 1.0)
                    return half4(scene.rgb, 1.0);

                // ── Precision-safe time ────────────────────────────────────────
                float safeTime = fmod(_Time.y, 3600.0);

                // ── Animated centre position ───────────────────────────────────
                float cx = _PositionX;
                float cy = _PositionY;

                #if defined(_ENABLE_MOTION)
                {
                    float motionT = 0.0;

                    #if defined(_MOTIONMODE_LOOP)
                        motionT = saturate(fmod(safeTime, _MotionDuration) / _MotionDuration);

                    #elif defined(_MOTIONMODE_ONCE)
                        float elapsed = max(0.0, _Time.y - _StartTime);
                        motionT = saturate(elapsed / _MotionDuration);

                    #else // PingPong
                        float pp = _MotionDuration * 2.0;
                        float lm = fmod(safeTime, pp);
                        motionT  = (lm < _MotionDuration)
                                 ? lm / _MotionDuration
                                 : 1.0 - (lm - _MotionDuration) / _MotionDuration;
                        motionT  = saturate(motionT);
                    #endif

                    float em = EaseInOut(motionT, _MotionEase);
                    cx = lerp(_PositionX, _TargetX, em);
                    cy = lerp(_PositionY, _TargetY, em);
                }
                #endif

                // ── Build display rect in normalised screen UV ─────────────────
                float halfW = min((texW * 0.5) / screenW, 0.5);
                float halfH = min((texH * 0.5) / screenH, 0.5);

                float left   = cx - halfW;
                float right  = cx + halfW;
                float bottom = cy - halfH;
                float top    = cy + halfH;

                // Outside rect → scene unchanged
                if (screenUV.x < left  || screenUV.x > right  ||
                    screenUV.y < bottom || screenUV.y > top)
                    return half4(scene.rgb, 1.0);

                // Remap to local tile UV [0,1]
                float2 uv;
                uv.x = (screenUV.x - left)  / (right - left);
                uv.y = (screenUV.y - bottom) / (top   - bottom);

                // ── Spritesheet frame sequencing ───────────────────────────────
                // Sequence: all frames in row 0 (col 0→N), then row 1 (col 0→N), etc.
                // Between each consecutive pair: hold A → morph A→B → hold B → ...
                //
                // Period per frame transition:
                //   | hold | morph | (no second hold — next frame's hold covers it)
                //
                // Timeline for totalFrames transitions:
                //   frame0 [hold][morph] frame1 [hold][morph] ... frameN-1 [hold][morph] (loops)

                float totalFrames  = max(_Cols * _Rows, 2.0);
                float holdTime     = _HoldDuration;
                float morphTime    = max(_CycleDuration, 0.01);
                float framePeriod  = holdTime + morphTime;
                float totalPeriod  = totalFrames * framePeriod;

                float cyclePos    = fmod(safeTime, totalPeriod);
                float frameSlot   = cyclePos / framePeriod;
                float frameIdxA   = floor(frameSlot);                           // 0 .. totalFrames-1
                float framePhase  = frac(frameSlot);                            // 0..1 within this slot

                // frameIdxB is the NEXT frame (wraps around)
                float frameIdxB = fmod(frameIdxA + 1.0, totalFrames);

                // tLinear: 0 during hold, ramps 0→1 during morph
                float tLinear = saturate((framePhase - holdTime / framePeriod)
                                         / (morphTime / framePeriod));

                float t = EaseInOut(tLinear, _EasePower);

                // ── Sequential two-phase transparency ─────────────────────────
                //   t=[0,  0.5]: frame B fades IN,  frame A stays solid
                //   t=[0.5, 1 ]: frame A fades OUT, frame B stays solid
                float tPhase1 = saturate(t * 2.0);
                float tPhase2 = saturate(t * 2.0 - 1.0);

                float s      = _BlendSharpness;
                float alphaB = smoothstep(0.5 - s, 0.5 + s, tPhase1);
                float alphaA = 1.0 - smoothstep(0.5 - s, 0.5 + s, tPhase2);

                // ── Get spritesheet rects for both frames ──────────────────────
                float4 rectA = FrameRect(frameIdxA, _Cols, _Rows);
                float4 rectB = FrameRect(frameIdxB, _Cols, _Rows);

                // ── Optical flow warp ──────────────────────────────────────────
                // Sample raw flow vectors from each frame at the unwarped tile UV.
                // RG channels encode flow as [0,1] → decode to [-1,+1].
                float4 rawA  = SampleFrame(uv, rectA);
                float4 rawB  = SampleFrame(uv, rectB);
                float2 flowA = rawA.rg * 2.0 - 1.0;
                float2 flowB = rawB.rg * 2.0 - 1.0;

                // Warp amount reduces as the frame becomes fully visible.
                float2 uvA = clamp(uv + flowA * (1.0 - alphaA) * _WarpStrength, 0.001, 0.999);
                float2 uvB = clamp(uv - flowB * (1.0 - alphaB) * _WarpStrength, 0.001, 0.999);

                float4 colA = SampleFrame(uvA, rectA);
                float4 colB = SampleFrame(uvB, rectB);

                // ── Alpha composite (Porter-Duff "B over A") ───────────────────
                float texAlphaA  = colA.a * alphaA;
                float texAlphaB  = colB.a * alphaB;
                float morphAlpha = texAlphaB + texAlphaA * (1.0 - texAlphaB);

                // ── RGB composite (alpha-weighted, un-pre-multiplied) ──────────
                float3 morphRGB = (colA.rgb * texAlphaA
                                + colB.rgb * texAlphaB * (1.0 - texAlphaA))
                                / max(morphAlpha, 0.0001);

                // ── Composite morph over scene ─────────────────────────────────
                float3 finalRGB = morphRGB * morphAlpha + scene.rgb * (1.0 - morphAlpha);

                return half4(finalRGB, 1.0);
            }
            ENDHLSL
        }
    }
}
