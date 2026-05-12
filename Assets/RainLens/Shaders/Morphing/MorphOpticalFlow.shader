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
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }
        Cull Off ZWrite Off ZTest Always

        Pass
        {
            Name "MorphOpticalFlow"

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment frag
            #pragma target 3.5

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
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

                // ── Time → t [0,1] with hold at each end ──────────────────────
                //
                //  One full period = _CycleDuration + 2 * _HoldDuration
                //
                //  |← hold →|←── blend A→B ──→|← hold →|←── blend B→A ──→|
                //  0                                                        period
                //
                //  We then fold the second half back so t always goes 0→1
                //  (ping-pong), meaning A and B swap roles every half-period.

                float hold     = _HoldDuration;
                float transit  = _CycleDuration * 0.5;          // half-cycle = one transition
                float period   = transit * 2.0 + hold * 2.0;    // full ping-pong period

                float localT   = fmod(_Time.y, period);         // position inside period

                // Map localT to a 0→1 blend value with flat hold regions
                //
                //   [0,          hold]          → t = 0   (hold on A)
                //   [hold,       hold+transit]  → t = 0→1 (A fades out, B fades in)
                //   [hold+transit, hold+transit+hold] → t = 1  (hold on B)
                //   [2*hold+transit, period]    → t = 1→0 (B fades out, A fades in)

                float t;
                if (localT < hold)
                {
                    t = 0.0;
                }
                else if (localT < hold + transit)
                {
                    t = (localT - hold) / transit;
                }
                else if (localT < hold * 2.0 + transit)
                {
                    t = 1.0;
                }
                else
                {
                    t = 1.0 - (localT - hold * 2.0 - transit) / transit;
                }

                // ── Sequential two-phase transparency ─────────────────────────
                //  t=[0,0.5]: TexB fades IN  (TexA stays solid)
                //  t=[0.5,1]: TexA fades OUT (TexB stays solid)
                float tPhase1 = saturate(t * 2.0);
                float tPhase2 = saturate(t * 2.0 - 1.0);

                float s = _BlendSharpness;
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

                // ── Blend ──────────────────────────────────────────────────────
                float blend = alphaB * 0.5 + (1.0 - alphaA) * 0.5;
                float4 col  = lerp(colA, colB, blend);
                return half4(col.rgb, 1.0);
            }
            ENDHLSL
        }
    }
}
