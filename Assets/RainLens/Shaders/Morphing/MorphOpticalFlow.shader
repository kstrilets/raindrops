Shader "Custom/Morphing/MorphOpticalFlow"
{
    Properties
    {
        _TexA           ("Texture A",           2D)            = "white" {}
        _TexB           ("Texture B",           2D)            = "white" {}
        _BlendT         ("Blend T",             Range(0,1))    = 0.5
        _WarpStrength   ("Warp Strength",       Range(0,0.3))  = 0.08
        _BlendSharpness ("Blend Sharpness",     Range(0.01,1)) = 0.2
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

                // ── Sequential transparency phases ─────────────────────────────
                //
                // Phase 1  t = 0.0 → 0.5 :  TexB fades IN   (alphaB: 0 → 1)
                //                            TexA stays fully visible (alphaA = 1)
                //
                // Phase 2  t = 0.5 → 1.0 :  TexB fully opaque (alphaB = 1)
                //                            TexA fades OUT  (alphaA: 1 → 0)
                //
                // _BlendSharpness controls softness at each phase boundary.

                float half_s = _BlendSharpness * 0.5;  // sharpness scaled to half-range

                // alphaB rises in the first half  [0, 0.5]
                float alphaB = smoothstep(0.5 - _BlendSharpness,
                                          0.5 + half_s, t);

                // alphaA falls in the second half  [0.5, 1]
                float alphaA = 1.0 - smoothstep(0.5 - half_s,
                                                 0.5 + _BlendSharpness, t);

                // ── Optical flow warp ──────────────────────────────────────────
                // Sample flow from unwarped UVs first
                float4 rawA  = SAMPLE_TEXTURE2D(_TexA, sampler_TexA, uv);
                float4 rawB  = SAMPLE_TEXTURE2D(_TexB, sampler_TexB, uv);
                float2 flowA = rawA.rg * 2.0 - 1.0;
                float2 flowB = rawB.rg * 2.0 - 1.0;

                // A warps forward driven by how far it has faded (alphaA receding)
                // B warps backward driven by how far it has appeared (alphaB arriving)
                float2 uvA = clamp(uv + flowA * (1.0 - alphaA) * _WarpStrength, 0.001, 0.999);
                float2 uvB = clamp(uv - flowB * (1.0 - alphaB) * _WarpStrength, 0.001, 0.999);

                float4 colA = SAMPLE_TEXTURE2D(_TexA, sampler_TexA, uvA);
                float4 colB = SAMPLE_TEXTURE2D(_TexB, sampler_TexB, uvB);

                // ── Composite: B over A using sequential alphas ────────────────
                // Both can be partially visible only in the narrow overlap window
                // around t = 0.5. Outside that window one of them is always fully
                // opaque so there is no double-transparency artefact.
                float3 col = colA.rgb * alphaA + colB.rgb * alphaB * (1.0 - alphaA);
                // Normalise so the result never goes dark when both alphas are < 1
                float totalAlpha = saturate(alphaA + alphaB * (1.0 - alphaA));
                col = col / max(totalAlpha, 0.001);

                return half4(col, 1.0);
            }
            ENDHLSL
        }
    }
}
