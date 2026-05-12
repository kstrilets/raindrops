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

        // Fullscreen pass blends on top of the already-rendered scene.
        // SrcAlpha / OneMinusSrcAlpha lets the scene show through wherever
        // both textures are transparent (finalAlpha = 0).
        Blend SrcAlpha OneMinusSrcAlpha
        Cull Off
        ZWrite Off
        ZTest Always          // fullscreen triangle must always pass depth

        Pass
        {
            Name "MorphOpticalFlow"

            HLSLPROGRAM
            // Blit.hlsl provides Vert (fullscreen procedural triangle) + Varyings.
            // This is correct for a ScriptableRenderPass / RenderGraph blit.
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
                //   |← hold →|←── A→B ──→|← hold →|←── B→A ──→| repeat
                float hold    = _HoldDuration;
                float transit = _CycleDuration * 0.5;
                float period  = transit * 2.0 + hold * 2.0;
                float localT  = fmod(_Time.y, period);

                float t;
                if      (localT < hold)                       t = 0.0;
                else if (localT < hold + transit)             t = (localT - hold) / transit;
                else if (localT < hold * 2.0 + transit)      t = 1.0;
                else                                          t = 1.0 - (localT - hold * 2.0 - transit) / transit;

                // ── Sequential two-phase transparency ─────────────────────────
                //   t=[0,  0.5]: TexB fades IN   — TexA stays solid
                //   t=[0.5, 1 ]: TexA fades OUT  — TexB stays solid
                float tPhase1 = saturate(t * 2.0);
                float tPhase2 = saturate(t * 2.0 - 1.0);

                float s      = _BlendSharpness;
                float alphaB = smoothstep(0.5 - s, 0.5 + s, tPhase1);
                float alphaA = 1.0 - smoothstep(0.5 - s, 0.5 + s, tPhase2);

                // ── Optical flow warp ──────────────────────────────────────────
                // Sample raw (unwarped) to get flow direction from RG channels
                float4 rawA  = SAMPLE_TEXTURE2D(_TexA, sampler_TexA, uv);
                float4 rawB  = SAMPLE_TEXTURE2D(_TexB, sampler_TexB, uv);
                float2 flowA = rawA.rg * 2.0 - 1.0;
                float2 flowB = rawB.rg * 2.0 - 1.0;

                // A warps outward as it fades; B warps inward as it arrives
                float2 uvA = clamp(uv + flowA * (1.0 - alphaA) * _WarpStrength, 0.001, 0.999);
                float2 uvB = clamp(uv - flowB * (1.0 - alphaB) * _WarpStrength, 0.001, 0.999);

                float4 colA = SAMPLE_TEXTURE2D(_TexA, sampler_TexA, uvA);
                float4 colB = SAMPLE_TEXTURE2D(_TexB, sampler_TexB, uvB);

                // ── Alpha composite (Porter-Duff "B over A") ───────────────────
                // Scale each texture's own alpha by its phase weight so:
                //   - A's silhouette disappears only during phase 2
                //   - B's silhouette appears only during phase 1
                //   - Areas transparent in both textures → finalAlpha = 0
                //     → scene background shows through via GPU blend state
                float texAlphaA  = colA.a * alphaA;
                float texAlphaB  = colB.a * alphaB;
                float finalAlpha = texAlphaB + texAlphaA * (1.0 - texAlphaB);

                // ── RGB composite ──────────────────────────────────────────────
                // Alpha-weighted blend so semi-transparent edge colours are correct.
                // Divide by finalAlpha to un-pre-multiply before handing to GPU blend.
                float3 rgb = (colA.rgb * texAlphaA + colB.rgb * texAlphaB * (1.0 - texAlphaA))
                             / max(finalAlpha, 0.0001);

                return half4(rgb, finalAlpha);
            }
            ENDHLSL
        }
    }
}
