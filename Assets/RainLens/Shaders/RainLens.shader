Shader "Custom/RainLens"
{
    Properties
    {
        [Header(Drop Layers)]
        _DropNormalMap("Drop Normal Map", 2D) = "bump" {}

        [Header(Layer A Large Drops)]
        _LayerACount("Count", Range(1,20)) = 8
        _LayerASpeed("Speed", Float) = 0.05
        _LayerASizeMin("Size Min", Range(0.02,0.3)) = 0.10
        _LayerASizeMax("Size Max", Range(0.02,0.3)) = 0.18
        _LayerADistort("Distortion", Range(0,0.08)) = 0.045
        _LayerALean("Max Lean", Range(0,0.5)) = 0.20

        [Header(Layer B Medium Drops)]
        _LayerBCount("Count", Range(1,20)) = 12
        _LayerBSpeed("Speed", Float) = 0.10
        _LayerBSizeMin("Size Min", Range(0.01,0.2)) = 0.05
        _LayerBSizeMax("Size Max", Range(0.01,0.2)) = 0.09
        _LayerBDistort("Distortion", Range(0,0.06)) = 0.025
        _LayerBLean("Max Lean", Range(0,0.5)) = 0.30

        [Header(Layer C Small Streaks)]
        _LayerCCount("Count", Range(1,24)) = 16
        _LayerCSpeed("Speed", Float) = 0.22
        _LayerCSizeMin("Size Min", Range(0.005,0.1)) = 0.02
        _LayerCSizeMax("Size Max", Range(0.005,0.1)) = 0.04
        _LayerCDistort("Distortion", Range(0,0.03)) = 0.010
        _LayerCLean("Max Lean", Range(0,0.5)) = 0.15

        [Header(Generation Morph)]
        _GenRate("Morph Rate", Range(0.1,4.0)) = 1.2
        _GenBlend("Morph Blend Window", Range(0.05,0.5)) = 0.22
        _GenPosJitter("Position Jitter", Range(0,0.06)) = 0.022
        _GenSizeJitter("Size Jitter", Range(0,0.4)) = 0.18
        _GenLeanJitter("Lean Jitter", Range(0,0.3)) = 0.12

        [Header(Dissolve)]
        _DissolveStart("Dissolve Start", Range(0,1)) = 0.74
        _DissolveEnd("Dissolve End", Range(0,1)) = 0.97

        [Header(Wetness)]
        _WetDistort("Global Wet Warp", Range(0,0.012)) = 0.003
        _WetSpeed("Wet Noise Speed", Float) = 0.12
        _Saturation("Saturation Boost", Range(1,2)) = 1.10
        _Darken("Wet Darken", Range(0,0.4)) = 0.08
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }
        Pass
        {
            Name "RainLens"
            Cull Off
            ZWrite Off
            ZTest Always

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment frag
            #pragma target 3.5

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            TEXTURE2D(_DropNormalMap);
            SAMPLER(sampler_DropNormalMap);

            CBUFFER_START(UnityPerMaterial)
                float _LayerACount;
                float _LayerASpeed;
                float _LayerASizeMin;
                float _LayerASizeMax;
                float _LayerADistort;
                float _LayerALean;

                float _LayerBCount;
                float _LayerBSpeed;
                float _LayerBSizeMin;
                float _LayerBSizeMax;
                float _LayerBDistort;
                float _LayerBLean;

                float _LayerCCount;
                float _LayerCSpeed;
                float _LayerCSizeMin;
                float _LayerCSizeMax;
                float _LayerCDistort;
                float _LayerCLean;

                float _GenRate;
                float _GenBlend;
                float _GenPosJitter;
                float _GenSizeJitter;
                float _GenLeanJitter;

                float _DissolveStart;
                float _DissolveEnd;

                float _WetDistort;
                float _WetSpeed;
                float _Saturation;
                float _Darken;
            CBUFFER_END

            static const float DROP_CULLING_RADIUS_MULTIPLIER = 1.8;
            static const float TRAIL_MASK_WEIGHT = 0.4;
            static const float LAYER_B_SEED = 31.7;
            static const float LAYER_C_SEED = 67.3;
            static const int MAX_DROP_COUNT = 24;

            float Hash11(float p)
            {
                p = frac(p * 0.1031);
                p *= p + 33.33;
                p *= p + p;
                return frac(p);
            }

            float Hash21(float2 p)
            {
                p = frac(p * float2(127.34, 311.71));
                p += dot(p, p + 47.53);
                return frac(p.x * p.y);
            }

            float ValueNoise(float2 p)
            {
                float2 i = floor(p);
                float2 f = frac(p);
                float2 u = f * f * (3.0 - 2.0 * f);

                float n00 = Hash21(i + float2(0.0, 0.0));
                float n10 = Hash21(i + float2(1.0, 0.0));
                float n01 = Hash21(i + float2(0.0, 1.0));
                float n11 = Hash21(i + float2(1.0, 1.0));

                return lerp(lerp(n00, n10, u.x), lerp(n01, n11, u.x), u.y);
            }

            float2 NoiseGrad(float2 p)
            {
                const float e = 0.005;
                float dx = ValueNoise(p + float2(e, 0.0)) - ValueNoise(p - float2(e, 0.0));
                float dy = ValueNoise(p + float2(0.0, e)) - ValueNoise(p - float2(0.0, e));
                return float2(dx, dy) / (2.0 * e);
            }

            struct GenData
            {
                float xJitter;
                float sizeScale;
                float lean;
            };

            GenData GetGenData(float di, float ls, float gen, float maxLean, float maxSize, float maxPos)
            {
                float baseValue = di * 100.0 + ls * 13.7 + gen * 7.3;
                GenData g;
                g.xJitter = Hash11(baseValue + 1.1) * 2.0 - 1.0;
                g.sizeScale = 1.0 + (Hash11(baseValue + 2.3) * 2.0 - 1.0) * maxSize;
                g.lean = (Hash11(baseValue + 3.7) * 2.0 - 1.0) * maxLean;
                return g;
            }

            float3 EvaluateDrop(float2 uv, float2 center, float size, float lean, float distortStr, float aspect)
            {
                float2 delta = float2((uv.x - center.x) * aspect, uv.y - center.y);
                if (length(delta) > size * DROP_CULLING_RADIUS_MULTIPLIER)
                {
                    return float3(0.0, 0.0, 0.0);
                }

                float cosL = cos(lean);
                float sinL = sin(lean);
                float2 rd = float2(cosL * delta.x - sinL * delta.y, sinL * delta.x + cosL * delta.y);
                float2 texUV = clamp(rd / size * 0.5 + 0.5, 0.0, 1.0);
                float4 ns = SAMPLE_TEXTURE2D_LOD(_DropNormalMap, sampler_DropNormalMap, texUV, 0);
                float2 n = ns.rg * 2.0 - 1.0;
                float mask = saturate(ns.b + ns.a * TRAIL_MASK_WEIGHT);
                return float3(n.x * distortStr * mask, n.y * distortStr * mask, mask);
            }

            float3 EvaluateLayer(
                float2 uv,
                float count,
                float speed,
                float sizeMin,
                float sizeMax,
                float distortStr,
                float maxLean,
                float layerSeed,
                float aspect)
            {
                float2 totalDistort = float2(0.0, 0.0);
                float maxMask = 0.0;

                [loop]
                for (int i = 0; i < MAX_DROP_COUNT; i++)
                {
                    if (i >= (int)count)
                    {
                        break;
                    }

                    float di = i + layerSeed;
                    float baseX = Hash11(di * 5.17 + layerSeed * 1.33);
                    float ySeed = Hash11(di * 9.71 + layerSeed * 2.11);
                    float fall = frac(_Time.y * speed + ySeed);
                    float y = 1.15 - fall * 2.30;

                    float genT = _Time.y * _GenRate + di * 0.618;
                    float genI = floor(genT);
                    float genF = frac(genT);
                    float morph = smoothstep(0.5 - _GenBlend, 0.5 + _GenBlend, genF);

                    GenData g0 = GetGenData(di, layerSeed, genI, _GenLeanJitter, _GenSizeJitter, _GenPosJitter);
                    GenData g1 = GetGenData(di, layerSeed, genI + 1.0, _GenLeanJitter, _GenSizeJitter, _GenPosJitter);
                    GenData g;
                    g.xJitter = lerp(g0.xJitter, g1.xJitter, morph);
                    g.sizeScale = lerp(g0.sizeScale, g1.sizeScale, morph);
                    g.lean = lerp(g0.lean, g1.lean, morph);

                    float sizeBase = lerp(sizeMin, sizeMax, Hash11(di * 3.71 + 9.2));
                    float size = max(0.001, sizeBase * g.sizeScale);
                    float centerX = frac(baseX + g.xJitter * _GenPosJitter + sin(_Time.y * speed + di) * 0.01);
                    float2 center = float2(centerX, y);

                    float dissolve = 1.0 - smoothstep(_DissolveStart, _DissolveEnd, fall);
                    float3 drop = EvaluateDrop(uv, center, size, g.lean, distortStr, aspect);
                    drop *= dissolve;

                    totalDistort += drop.xy;
                    maxMask = max(maxMask, drop.z);
                }

                return float3(totalDistort, maxMask);
            }

            half4 frag(Varyings IN) : SV_Target
            {
                float2 uv = IN.texcoord;
                float aspect = _ScreenParams.x / _ScreenParams.y;

                float2 wetNoiseUV = uv * 7.0 + float2(0.0, _Time.y * _WetSpeed);
                float2 wetWarp = NoiseGrad(wetNoiseUV) * _WetDistort;

                float3 layerA = EvaluateLayer(uv, _LayerACount, _LayerASpeed, _LayerASizeMin, _LayerASizeMax, _LayerADistort, _LayerALean, 0.0, aspect);
                float3 layerB = EvaluateLayer(uv, _LayerBCount, _LayerBSpeed, _LayerBSizeMin, _LayerBSizeMax, _LayerBDistort, _LayerBLean, LAYER_B_SEED, aspect);
                float3 layerC = EvaluateLayer(uv, _LayerCCount, _LayerCSpeed, _LayerCSizeMin, _LayerCSizeMax, _LayerCDistort, _LayerCLean, LAYER_C_SEED, aspect);

                float2 distort = wetWarp + layerA.xy + layerB.xy + layerC.xy;
                float mask = saturate(max(layerA.z, max(layerB.z, layerC.z)));

                float2 sampleUV = saturate(uv + distort);
                half4 color = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, sampleUV);

                color.rgb *= 1.0 - (_Darken * mask);
                float luma = dot(color.rgb, float3(0.2126, 0.7152, 0.0722));
                color.rgb = lerp(luma.xxx, color.rgb, 1.0 + (_Saturation - 1.0) * mask);

                return color;
            }
            ENDHLSL
        }
    }
}
