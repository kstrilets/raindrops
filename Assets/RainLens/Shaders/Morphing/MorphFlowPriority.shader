Shader "Custom/Morphing/MorphFlowPriority"
{
    // Combined: Height Priority (Variant 3) drives WHICH pixels transition first.
    // Optical Flow Warp (Variant 2) makes the transition look like flowing liquid.

    Properties
    {
        _TexA           ("Texture A",           2D)            = "white" {}
        _TexB           ("Texture B",           2D)            = "white" {}
        _BlendT         ("Blend T",             Range(0,1))    = 0.5
        _WarpStrength   ("Warp Strength",       Range(0,0.3))  = 0.08
        _BlendSharpness ("Blend Sharpness",     Range(0.05,2)) = 0.25
        _FlowInfluence  ("Flow Influence",      Range(0,1))    = 0.6
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }
        Cull Off ZWrite Off ZTest Always

        Pass
        {
            Name "MorphFlowPriority"

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
                float _FlowInfluence;
            CBUFFER_END

            half4 frag(Varyings IN) : SV_Target
            {
                float2 uv = IN.texcoord;
                float  t  = _BlendT;

                // ── Step 1: Height priority blend factor ──────────────────
                float4 rawA    = SAMPLE_TEXTURE2D(_TexA, sampler_TexA, uv);
                float4 rawB    = SAMPLE_TEXTURE2D(_TexB, sampler_TexB, uv);

                float heightA  = rawA.b;
                float heightB  = rawB.b;
                float priority = heightA - heightB;

                float blendFactor = saturate(
                    ((t * 2.0 - 1.0) + priority)
                    / max(_BlendSharpness, 0.05) * 0.5 + 0.5
                );

                // ── Step 2: Optical flow warp ─────────────────────────────
                // Peak warp at blendFactor=0.5 (midpoint), zero at 0 and 1
                float warpPeak = 1.0 - abs(blendFactor * 2.0 - 1.0);

                float2 flowA = rawA.rg * 2.0 - 1.0;
                float2 flowB = rawB.rg * 2.0 - 1.0;

                float2 uvA = clamp(
                    uv + flowA * blendFactor       * _WarpStrength * warpPeak * _FlowInfluence,
                    0.001, 0.999);
                float2 uvB = clamp(
                    uv - flowB * (1.0 - blendFactor) * _WarpStrength * warpPeak * _FlowInfluence,
                    0.001, 0.999);

                // ── Step 3: Re-sample with warped UVs ────────────────────
                float4 colA = SAMPLE_TEXTURE2D(_TexA, sampler_TexA, uvA);
                float4 colB = SAMPLE_TEXTURE2D(_TexB, sampler_TexB, uvB);

                // ── Step 4: Blend using height-priority factor ────────────
                float4 col  = lerp(colA, colB, blendFactor);
                return half4(col.rgb, 1.0);
            }
            ENDHLSL
        }
    }
}
