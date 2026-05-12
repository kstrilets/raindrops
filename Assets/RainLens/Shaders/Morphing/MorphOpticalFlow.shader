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
        _PositionX       ("Position X (0=left, 1=right)", Range(0,1)) = 0.5
        _PositionY       ("Position Y (0=bottom, 1=top)", Range(0,1)) = 0.5
        [Header(Time Control)]
        _CycleDuration  ("Cycle Duration (sec)",   Range(0.5, 20.0)) = 4.0
        _HoldDuration   ("Hold Duration (sec)",    Range(0.0, 10.0)) = 1.0
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

            CBUFFER_START(UnityPerMaterial)
                float _UseTextureSize;
                float _TexWidthPixels;
                float _TexHeightPixels;
                float _PositionX;
                float _PositionY;
                float _CycleDuration;
                float _HoldDuration;
                float _WarpStrength;
                float _BlendSharpness;
            CBUFFER_END

            half4 frag(Varyings IN) : SV_Target
            {
                float2 screenUV = IN.texcoord;

                // ── Scene passthrough (always sampled, returned when outside rect) ──
                float4 scene = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, screenUV);

                // ── Compute texture rect in UV space ───────────────────────────
                // _ScreenParams.xy = (screenWidth, screenHeight) in pixels
                float screenW = _ScreenParams.x;
                float screenH = _ScreenParams.y;

                float texW, texH;

                #if defined(_USE_TEXTURE_SIZE)
                    // Use the resolution of TexA as the display size.
                    // _TexA_TexelSize.zw = (width, height) in pixels.
                    texW = _TexA_TexelSize.z;
                    texH = _TexA_TexelSize.w;
                #else
                    texW = _TexWidthPixels;
                    texH = _TexHeightPixels;
                #endif

                // Normalised half-extents in UV space
                float halfW = (texW * 0.5) / screenW;
                float halfH = (texH * 0.5) / screenH;

                // Centre of the rect in UV space
                float cx = _PositionX;
                float cy = _PositionY;

                // Rect bounds
                float left   = cx - halfW;
                float right  = cx + halfW;
                float bottom = cy - halfH;
                float top    = cy + halfH;

                // If the current pixel is outside the rect → return scene unchanged
                if (screenUV.x < left  || screenUV.x > right ||
                    screenUV.y < bottom || screenUV.y > top)
                {
                    return half4(scene.rgb, 1.0);
                }

                // Remap screen UV into the texture's local [0,1] UV space
                float2 uv;
                uv.x = (screenUV.x - left)   / (right  - left);
                uv.y = (screenUV.y - bottom)  / (top    - bottom);

                // ── Drive t automatically over time (ping-pong) ───────────────
                float hold    = _HoldDuration;
                float transit = _CycleDuration * 0.5;
                float period  = transit * 2.0 + hold * 2.0;
                float localT  = fmod(_Time.y, period);

                float t;
                if      (localT < hold)                      t = 0.0;
                else if (localT < hold + transit)            t = (localT - hold) / transit;
                else if (localT < hold * 2.0 + transit)     t = 1.0;
                else                                         t = 1.0 - (localT - hold * 2.0 - transit) / transit;

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

                // ── Manual over-composite against scene ───────────────────────
                float3 finalRGB = morphRGB * morphAlpha + scene.rgb * (1.0 - morphAlpha);

                return half4(finalRGB, 1.0);
            }
            ENDHLSL
        }
    }

    // Expose _TexA_TexelSize so the shader can read actual texture dimensions
    CustomEditor "UnityEditor.ShaderGUI"
}
