Shader "Custom/Morphing/MorphOpticalFlow"
{
    Properties
    {
        _TexA           ("Texture A",              2D)               = "white" {}
        _TexB           ("Texture B",              2D)               = "white" {}
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

        // No GPU blending — we composite manually against _BlitTexture (scene).
        // This is the correct pattern for a URP fullscreen render feature blit.
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

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            // Blit.hlsl provides:
            //   - Vert()            fullscreen procedural triangle vertex shader
            //   - Varyings          struct with texcoord
            //   - _BlitTexture      the source camera color (scene)
            //   - sampler_LinearClamp
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            TEXTURE2D(_TexA); SAMPLER(sampler_TexA);
            TEXTURE2D(_TexB); SAMPLER(sampler_TexB);

            CBUFFER_START(UnityPerMaterial)
                float _CycleDuration;
                float _HoldDuration;
                float _WarpStrength;
                float _BlendSharpness;
            CBUFFER_END

            half4 frag(Varyings IN) : SV_Target
            {
                float2 uv = IN.texcoord;

                // ── Sample the scene (what was rendered before this pass) ──────
                float4 scene = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv);

                // ── Drive t automatically over time (ping-pong) ───────────────
                //   |← hold →|←── A→B ──→|← hold →|←── B→A ──→| repeat
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

                // ── RGB composite ──────────────────────────────────────────────
                // Alpha-weighted morph colour (un-pre-multiplied)
                float3 morphRGB = (colA.rgb * texAlphaA + colB.rgb * texAlphaB * (1.0 - texAlphaA))
                                  / max(morphAlpha, 0.0001);

                // ── Manual over-composite against the scene ────────────────────
                // morphAlpha=0 → scene shows through fully
                // morphAlpha=1 → morph result covers scene fully
                float3 finalRGB = morphRGB * morphAlpha + scene.rgb * (1.0 - morphAlpha);

                return half4(finalRGB, 1.0);
            }
            ENDHLSL
        }
    }
}
