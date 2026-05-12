Shader "Custom/Morphing/MorphOpticalFlow"
{
    Properties
    {
        _TexA           ("Texture A",           2D)            = "white" {}
        _TexB           ("Texture B",           2D)            = "white" {}
        _BlendT         ("Blend T",             Range(0,1))    = 0.5
        _WarpStrength   ("Warp Strength",       Range(0,0.3))  = 0.08
        _BlendSharpness ("Blend Sharpness",     Range(0.01,0.49)) = 0.2
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
                float _BlendT;
                float _WarpStrength;
                float _BlendSharpness;
            CBUFFER_END

            half4 frag(Varyings IN) : SV_Target
            {
                float2 uv = IN.texcoord;
                float  t  = _BlendT;

                // ── Sequential phases ──────────────────────────────────────────
                //
                //  t = 0.0 ──────── 0.5 ──────── 1.0
                //
                //  tPhase1:  0 ────── 1 ────────── 1   (ramps over first half only)
                //  tPhase2:  0 ────── 0 ────────── 1   (ramps over second half only)
                //
                //  alphaB rises during phase 1  →  TexB fades IN,  TexA stays solid
                //  alphaA falls during phase 2  →  TexA fades OUT, TexB stays solid
                //
                //  The two windows are guaranteed non-overlapping because
                //  phase1 is fully done before phase2 begins.

                float tPhase1 = saturate(t * 2.0);          // 0→1 mapped to t=[0,  0.5]
                float tPhase2 = saturate(t * 2.0 - 1.0);   // 0→1 mapped to t=[0.5,1.0]

                float s = _BlendSharpness;   // max 0.49 so window stays inside [0,1]

                float alphaB = smoothstep(0.5 - s, 0.5 + s, tPhase1);
                float alphaA = 1.0 - smoothstep(0.5 - s, 0.5 + s, tPhase2);

                // ── Optical flow warp ──────────────────────────────────────────
                // Get flow vectors from unwarped samples first
                float4 rawA  = SAMPLE_TEXTURE2D(_TexA, sampler_TexA, uv);
                float4 rawB  = SAMPLE_TEXTURE2D(_TexB, sampler_TexB, uv);
                float2 flowA = rawA.rg * 2.0 - 1.0;
                float2 flowB = rawB.rg * 2.0 - 1.0;

                // A pushes outward as it fades (alphaA dropping → 1-alphaA rising)
                // B pulls inward as it arrives (alphaB rising → 1-alphaB falling)
                float2 uvA = clamp(uv + flowA * (1.0 - alphaA) * _WarpStrength, 0.001, 0.999);
                float2 uvB = clamp(uv - flowB * (1.0 - alphaB) * _WarpStrength, 0.001, 0.999);

                float4 colA = SAMPLE_TEXTURE2D(_TexA, sampler_TexA, uvA);
                float4 colB = SAMPLE_TEXTURE2D(_TexB, sampler_TexB, uvB);

                // ── Blend ──────────────────────────────────────────────────────
                // Single blend factor derived from the two sequential alphas:
                //   phase 1 only alphaB moves  → blend goes 0 → 0.5
                //   phase 2 only alphaA moves  → blend goes 0.5 → 1
                // Result: standard lerp but paced in two non-overlapping steps.
                float blend = alphaB * 0.5 + (1.0 - alphaA) * 0.5;

                float4 col = lerp(colA, colB, blend);
                return half4(col.rgb, 1.0);
            }
            ENDHLSL
        }
    }
}
