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
            "RenderType"      = "Transparent"
            "RenderPipeline"  = "UniversalPipeline"
            "Queue"           = "Transparent"
        }

        // Standard alpha blending: src_alpha over (1 - src_alpha) background
        Blend SrcAlpha OneMinusSrcAlpha
        ZWrite Off
        Cull Off
        ZTest LEqual

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

                // ── Drive t automatically over time ────────────────────────────
                //
                //   |← hold →|←── A→B ──→|← hold →|←── B→A ──→| repeat
                //
                float hold    = _HoldDuration;
                float transit = _CycleDuration * 0.5;
                float period  = transit * 2.0 + hold * 2.0;
                float localT  = fmod(_Time.y, period);

                float t;
                if      (localT < hold)                         t = 0.0;
                else if (localT < hold + transit)               t = (localT - hold) / transit;
                else if (localT < hold * 2.0 + transit)         t = 1.0;
                else                                            t = 1.0 - (localT - hold * 2.0 - transit) / transit;

                // ── Sequential two-phase transparency ─────────────────────────
                //  t=[0, 0.5]: TexB fades IN   — TexA stays solid
                //  t=[0.5, 1]: TexA fades OUT  — TexB stays solid
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

                // ── Blend RGB and Alpha separately ────────────────────────────
                //
                // blend drives lerp: 0 = fully A, 1 = fully B
                float blend = alphaB * 0.5 + (1.0 - alphaA) * 0.5;

                float3 rgb = lerp(colA.rgb, colB.rgb, blend);

                // Alpha: composite B's texture-alpha ON TOP of A's using the
                // sequential per-phase weights, then lerp to the final state.
                // This ensures:
                //   - A's shape silhouette fades out only after B's is fully in
                //   - Areas fully transparent in both textures stay transparent
                float texAlphaA = colA.a * alphaA;           // A's shape, weighted by its phase
                float texAlphaB = colB.a * alphaB;           // B's shape, weighted by its phase
                // Standard "B over A" alpha compositing formula
                float finalAlpha = texAlphaB + texAlphaA * (1.0 - texAlphaB);

                return half4(rgb, finalAlpha);
            }
            ENDHLSL
        }
    }
}
