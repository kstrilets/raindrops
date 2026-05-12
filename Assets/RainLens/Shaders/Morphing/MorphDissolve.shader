Shader "Custom/Morphing/MorphDissolve"
{
    Properties
    {
        _TexA           ("Texture A",           2D)           = "white" {}
        _TexB           ("Texture B",           2D)           = "white" {}
        _NoiseTex       ("Noise Mask",          2D)           = "white" {}
        _Threshold      ("Dissolve Threshold",  Range(0,1))   = 0.5
        _EdgeWidth      ("Edge Width",          Range(0,0.15))= 0.04
        _EdgeBrightness ("Edge Brightness",     Range(0,3))   = 1.5
        _EdgeColor      ("Edge Tint",           Color)        = (1,1,1,1)
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }
        Cull Off ZWrite Off ZTest Always

        Pass
        {
            Name "MorphDissolve"

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment frag
            #pragma target 3.5

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            TEXTURE2D(_TexA);     SAMPLER(sampler_TexA);
            TEXTURE2D(_TexB);     SAMPLER(sampler_TexB);
            TEXTURE2D(_NoiseTex); SAMPLER(sampler_NoiseTex);

            CBUFFER_START(UnityPerMaterial)
                float  _Threshold;
                float  _EdgeWidth;
                float  _EdgeBrightness;
                float4 _EdgeColor;
            CBUFFER_END

            half4 frag(Varyings IN) : SV_Target
            {
                float2 uv   = IN.texcoord;
                float4 colA = SAMPLE_TEXTURE2D(_TexA,     sampler_TexA,     uv);
                float4 colB = SAMPLE_TEXTURE2D(_TexB,     sampler_TexB,     uv);
                float  noise= SAMPLE_TEXTURE2D(_NoiseTex, sampler_NoiseTex, uv).r;

                // Which texture shows at this pixel
                float  inB  = step(noise, _Threshold);
                float4 base = lerp(colA, colB, inB);

                // Rim at the threshold boundary
                float edgeLo = smoothstep(_Threshold,
                                          _Threshold + _EdgeWidth, noise);
                float edgeHi = smoothstep(_Threshold + _EdgeWidth,
                                          _Threshold + _EdgeWidth * 2.0, noise);
                float rim    = edgeLo - edgeHi;
                base.rgb    += rim * _EdgeColor.rgb * _EdgeBrightness;

                return half4(base.rgb, 1.0);
            }
            ENDHLSL
        }
    }
}
