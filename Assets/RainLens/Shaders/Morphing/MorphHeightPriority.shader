Shader "Custom/Morphing/MorphHeightPriority"
{
    Properties
    {
        _TexA           ("Texture A",           2D)            = "white" {}
        _TexB           ("Texture B",           2D)            = "white" {}
        _BlendT         ("Blend T",             Range(0,1))    = 0.5
        _BlendSharpness ("Blend Sharpness",     Range(0.05,2)) = 0.25
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }
        Cull Off ZWrite Off ZTest Always

        Pass
        {
            Name "MorphHeightPriority"

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
                float _BlendSharpness;
            CBUFFER_END

            half4 frag(Varyings IN) : SV_Target
            {
                float2 uv = IN.texcoord;

                float4 colA    = SAMPLE_TEXTURE2D(_TexA, sampler_TexA, uv);
                float4 colB    = SAMPLE_TEXTURE2D(_TexB, sampler_TexB, uv);

                // B channel = drop mask = height proxy
                float heightA  = colA.b;
                float heightB  = colB.b;

                // Taller surface resists transition — priority > 0 means A holds longer
                float priority = heightA - heightB;

                // Time bias pushes toward B; priority offsets locally
                float blendFactor = saturate(
                    ((_BlendT * 2.0 - 1.0) + priority)
                    / max(_BlendSharpness, 0.05) * 0.5 + 0.5
                );

                float4 col = lerp(colA, colB, blendFactor);
                return half4(col.rgb, 1.0);
            }
            ENDHLSL
        }
    }
}
