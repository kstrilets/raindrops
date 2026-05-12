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

                // Sample flow directions from each texture's normal XY (RG channels)
                float4 rawA  = SAMPLE_TEXTURE2D(_TexA, sampler_TexA, uv);
                float4 rawB  = SAMPLE_TEXTURE2D(_TexB, sampler_TexB, uv);
                float2 flowA = rawA.rg * 2.0 - 1.0;
                float2 flowB = rawB.rg * 2.0 - 1.0;

                // Warp A forward in time, B backward
                float2 uvA = clamp(uv + flowA * t * _WarpStrength,         0.001, 0.999);
                float2 uvB = clamp(uv - flowB * (1.0 - t) * _WarpStrength, 0.001, 0.999);

                float4 colA = SAMPLE_TEXTURE2D(_TexA, sampler_TexA, uvA);
                float4 colB = SAMPLE_TEXTURE2D(_TexB, sampler_TexB, uvB);

                // Blend centred at t=0.5 with configurable sharpness
                float  blend = smoothstep(0.5 - _BlendSharpness,
                                          0.5 + _BlendSharpness, t);
                float4 col   = lerp(colA, colB, blend);

                return half4(col.rgb, 1.0);
            }
            ENDHLSL
        }
    }
}
