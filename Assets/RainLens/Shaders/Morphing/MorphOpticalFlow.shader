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
        _PositionX       ("Position X (0=left 1=right)", Range(0,1)) = 0.5
        _PositionY       ("Position Y (0=bottom 1=top)", Range(0,1)) = 0.5
        [Header(Time Control)]
        _CycleDuration  ("Cycle Duration (sec)",   Range(0.5, 20.0)) = 4.0
        _HoldDuration   ("Hold Duration (sec)",    Range(0.0, 10.0)) = 1.0
        [Header(Easing slow start then fast)]
        _EasePower      ("Ease Power (1=linear 3=strong)", Range(1.0, 5.0)) = 2.0
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

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            TEXTURE2D(_TexA); SAMPLER(sampler_TexA);
            TEXTURE2D(_TexB); SAMPLER(sampler_TexB);

            // _TexA_TexelSize must be declared OUTSIDE the CBUFFER —
            // Unity injects it automatically when _TexA is a sampler property.
            // Format: float4(1/width, 1/height, width, height)
            float4 _TexA_TexelSize;

            CBUFFER_START(UnityPerMaterial)
                float _UseTextureSize;
                float _TexWidthPixels;
                float _TexHeightPixels;
                float _PositionX;
                float _PositionY;
                float _CycleDuration;
                float _HoldDuration;
                float _EasePower;
                float _WarpStrength;
                float _BlendSharpness;
            CBUFFER_END

            // Ease-in then ease-out within one phase: slow → fast → slow
            // pow curve flipped so it accelerates in the middle of the transition.
            // We use a "smoothstep-like" curve: slow at 0, fast at 0.5, slow at 1.
            // For slow-start-fast-end within one phase: use pow(x, _EasePower).
            float EaseInOut(float x, float power)
            {
                // Piecewise: first half ease-in, second half ease-out
                // Gives slow→fast→slow feel across [0,1]
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
                    // _TexA_TexelSize.zw = (width, height) injected by Unity
                    texW = _TexA_TexelSize.z;
                    texH = _TexA_TexelSize.w;
                #else
                    texW = _TexWidthPixels;
                    texH = _TexHeightPixels;
                #endif

                // Guard against degenerate size (e.g. texture not yet assigned)
                if (texW < 1.0 || texH < 1.0)
                    return half4(scene.rgb, 1.0);

                // ── Compute rect in normalised screen UV ───────────────────────
                float screenW = _ScreenParams.x;
                float screenH = _ScreenParams.y;

                float halfW = (texW * 0.5) / screenW;
                float halfH = (texH * 0.5) / screenH;

                float left   = _PositionX - halfW;
                float right  = _PositionX + halfW;
                float bottom = _PositionY - halfH;
                float top    = _PositionY + halfH;

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

                // ── Drive t over time (ping-pong with hold regions) ────────────
                //   |← hold →|←── A→B ──→|← hold →|←── B→A ──→| repeat
                float hold    = _HoldDuration;
                float transit = _CycleDuration * 0.5;
                float period  = transit * 2.0 + hold * 2.0;
                float localT  = fmod(_Time.y, period);

                float tLinear;
                if      (localT < hold)                       tLinear = 0.0;
                else if (localT < hold + transit)             tLinear = (localT - hold) / transit;
                else if (localT < hold * 2.0 + transit)      tLinear = 1.0;
                else                                          tLinear = 1.0 - (localT - hold * 2.0 - transit) / transit;

                // ── Non-linear easing: slow start → fast middle ────────────────
                // EaseInOut maps linear tLinear to a curved t.
                // _EasePower=1 → linear, =2 → moderate, =4 → very slow start/end
                float t = EaseInOut(tLinear, _EasePower);

                // ── Sequential two-phase transparency ─────────────────────────
                //   t=[0,  0.5]: TexB fades IN   — TexA stays solid
                //   t=[0.5, 1 ]: TexA fades OUT  — TexB stays solid
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

                // ── RGB composite (alpha-weighted, un-pre-multiplied) ──────────
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
