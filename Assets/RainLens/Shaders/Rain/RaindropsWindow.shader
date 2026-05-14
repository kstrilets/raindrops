Shader "Custom/Rain/RaindropsWindow"
{
    Properties
    {
        [Header(Appearance)]
        _DropColor           ("Drop Tint Color",              Color)            = (0.8, 0.9, 1.0, 0.3)
        _Transparency        ("Overall Transparency",         Range(0.0, 1.0))  = 0.85
        _RefractionStrength  ("Refraction Strength",          Range(0.0, 1.0))  = 0.5
        _ReflectionStrength  ("Reflection Highlight",         Range(0.0, 3.0))  = 1.0
        _ReflectionColor     ("Reflection Color",             Color)            = (1.0, 1.0, 1.0, 1.0)
        _ReflectionSharpness ("Reflection Sharpness",         Range(4.0, 128.0))= 48.0

        [Header(Drop Shape)]
        _DropSize            ("Drop Size",                    Range(0.01, 0.25))= 0.08
        _DropDensity         ("Drop Density (rows)",          Range(2.0, 24.0)) = 8.0
        _TrailLength         ("Trail Length",                 Range(0.0, 1.0))  = 0.35
        _TrailOpacity        ("Trail Opacity",                Range(0.0, 1.0))  = 0.55
        _TrailWidth          ("Trail Width",                  Range(0.1, 1.0))  = 0.3

        [Header(Motion)]
        _DropSpeed           ("Fall Speed",                   Range(0.0, 6.0))  = 1.2
        _SpeedVariance       ("Speed Variance",               Range(0.0, 1.0))  = 0.6
        _WindStrength        ("Wind (horizontal drift)",      Range(-1.0, 1.0)) = 0.05

        [Header(Wetness)]
        _WetnessStrength     ("Background Wetness",           Range(0.0, 1.0))  = 0.25
        _WetnessScale        ("Wetness Noise Scale",          Range(1.0, 24.0)) = 8.0
        _WetnessSpeed        ("Wetness Flow Speed",           Range(0.0, 1.0))  = 0.04
    }

    SubShader
    {
        Tags
        {
            "RenderType"     = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
        }

        Blend Off
        Cull Off
        ZWrite Off
        ZTest Always

        Pass
        {
            Name "RaindropsWindow"

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment frag
            #pragma target 3.5

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _DropColor;
                float  _Transparency;
                float  _RefractionStrength;
                float  _ReflectionStrength;
                float4 _ReflectionColor;
                float  _ReflectionSharpness;
                float  _DropSize;
                float  _DropDensity;
                float  _TrailLength;
                float  _TrailOpacity;
                float  _TrailWidth;
                float  _DropSpeed;
                float  _SpeedVariance;
                float  _WindStrength;
                float  _WetnessStrength;
                float  _WetnessScale;
                float  _WetnessSpeed;
            CBUFFER_END

            // ── Pseudo-random helpers ──────────────────────────────────────────

            float hash1(float2 p)
            {
                return frac(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
            }

            float2 hash2(float2 p)
            {
                return frac(sin(float2(dot(p, float2(127.1, 311.7)),
                                       dot(p, float2(269.5, 183.3)))) * 43758.5453);
            }

            float valueNoise(float2 uv)
            {
                float2 i = floor(uv);
                float2 f = frac(uv);
                float2 u = f * f * (3.0 - 2.0 * f);
                float  a = hash1(i);
                float  b = hash1(i + float2(1.0, 0.0));
                float  c = hash1(i + float2(0.0, 1.0));
                float  d = hash1(i + float2(1.0, 1.0));
                return lerp(lerp(a, b, u.x), lerp(c, d, u.x), u.y);
            }

            // ── Single raindrop grid layer ─────────────────────────────────────
            // dropUV is a GRAVITY-SPACE UV where:
            //   x = 0 (left) → 1 (right)   — same as screen
            //   y = 0 (top)  → 1 (bottom)  — FLIPPED from Blit UV
            // This keeps all drop/trail logic platform-independent.
            //
            // Returns:
            //   .xy = refraction offset in GRAVITY-SPACE UV (will be unflipped on output)
            //   .z  = combined opacity mask [0,1]
            //   .w  = specular highlight    [0,1]
            float4 RaindropLayer(
                float2 dropUV,      // gravity-space UV (y=0 top, y=1 bottom)
                float  aspect,
                float  safeTime,
                float  density,
                float  speedMult,
                float  sizeMult)
            {
                float cols       = max(1.0, round(density * aspect));
                float rows       = density;
                float cellAspect = (aspect * rows) / cols;

                float2 gridUV = float2(dropUV.x * cols, dropUV.y * rows);
                float2 cellID = floor(gridUV);
                float2 cellUV = frac(gridUV);   // [0,1] within cell, y=0 top, y=1 bottom

                float2 rnd  = hash2(cellID);
                float  rnd1 = hash1(cellID + float2(3.7, 1.3));
                float  rnd2 = hash1(cellID + float2(8.1, 4.6));

                // Random X rest position [0.15, 0.85]
                float dropX = 0.15 + rnd.x * 0.70;

                // Per-drop fall speed
                float speed = speedMult * max(0.05,
                              1.0 - _SpeedVariance * 0.5 + _SpeedVariance * rnd.y);

                // phase 0→1: drop travels y=0 (top) → y=1 (bottom), wraps
                float phase = frac(safeTime * speed * 0.1 + rnd1);
                float dropY = phase;    // y=0 top → y=1 bottom (gravity space)

                // Horizontal wind drift: accumulates as drop falls
                float dropXt = saturate(dropX + _WindStrength * phase * 0.12
                                        * (rnd2 * 2.0 - 1.0));

                // ── Drop SDF ───────────────────────────────────────────────────
                float2 dropCenter = float2(dropXt, dropY);
                float2 d          = cellUV - dropCenter;
                d.x              *= cellAspect;
                float dropDist    = length(d);

                float radius   = _DropSize * sizeMult;
                float dropMask = 1.0 - smoothstep(radius - 0.018, radius + 0.018, dropDist);

                // ── Trail: streak at LOWER y values (above the drop = where it was) ──
                // In gravity space: trail region is cellUV.y < dropY
                float trailMask = 0.0;
                float behind    = dropY - cellUV.y;   // > 0 = above drop = trail region

                if (behind > 0.001 && behind < _TrailLength)
                {
                    // Reconstruct historical X at this Y (matching wind curve)
                    float histPhase = cellUV.y;   // phase when drop was at this Y
                    float histX     = saturate(dropX + _WindStrength * histPhase * 0.12
                                               * (rnd2 * 2.0 - 1.0));

                    float trailHalfW = radius * _TrailWidth / max(cellAspect, 0.001);
                    float xDist      = abs(cellUV.x - histX);

                    if (xDist < trailHalfW)
                    {
                        float xFade    = 1.0 - (xDist / max(trailHalfW, 0.001));
                        float yFade    = 1.0 - (behind / _TrailLength);
                        float joinFade = smoothstep(0.0, radius * 0.5, behind);
                        trailMask      = saturate(xFade * yFade * joinFade) * _TrailOpacity;
                    }
                }

                // ── Surface normal + refraction ────────────────────────────────
                float2 normal2D = float2(d.x / max(cellAspect, 0.001), d.y)
                                  / max(dropDist, 0.001);

                float2 refractOff  = -normal2D * dropMask * _RefractionStrength * 0.045;
                refractOff        += float2(0.0, (rnd.y - 0.5) * 0.003) * trailMask;

                // ── Specular (light from top-left in gravity space) ────────────
                float2 lightDir = normalize(float2(-0.4, -0.7));
                float  spec     = pow(saturate(dot(-normal2D, lightDir)),
                                      max(_ReflectionSharpness, 1.0)) * dropMask;

                float combinedMask = saturate(dropMask + trailMask * (1.0 - dropMask));

                return float4(refractOff, combinedMask, spec);
            }

            half4 frag(Varyings IN) : SV_Target
            {
                // screenUV from Blit.hlsl: covers [0,1]×[0,1] over the full screen.
                // Y-direction depends on platform (DX: y=0 top; GL: y=0 bottom).
                float2 screenUV = IN.texcoord;

                // Guard: _ScreenParams can be (1,1) during early blit passes
                float screenW = _ScreenParams.x;
                float screenH = _ScreenParams.y;
                if (screenW < 2.0 || screenH < 2.0)
                    return SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, screenUV);

                float aspect   = screenW / screenH;
                float safeTime = fmod(_Time.y, 3600.0);

                // ── Convert screenUV → gravity-space UV ────────────────────────
                // We normalise Y so that y=0 always means TOP OF SCREEN and y=1
                // means BOTTOM OF SCREEN regardless of platform UV conventions.
                // On DX/Metal: _ProjectionParams.x = 1  (y=0 is already top → no flip)
                // On GL:       _ProjectionParams.x = -1 (y=0 is bottom → flip)
                float2 dropUV = screenUV;
                #if UNITY_UV_STARTS_AT_TOP
                    // DX/Metal/Vulkan: Blit.hlsl already places y=0 at top — no flip needed
                #else
                    // OpenGL: y=0 is at bottom, flip so y=0 = top
                    dropUV.y = 1.0 - screenUV.y;
                #endif

                // ── Two raindrop layers ────────────────────────────────────────
                float4 layerA = RaindropLayer(dropUV, aspect, safeTime,
                    _DropDensity,         _DropSpeed,        1.0);

                float4 layerB = RaindropLayer(dropUV, aspect, safeTime + 17.3,
                    _DropDensity * 1.75,  _DropSpeed * 1.55, 0.55);

                // Composite: B underneath, A on top
                float  aZ           = layerA.z;
                float2 refractOff   = layerA.xy + layerB.xy * (1.0 - aZ);
                float  combinedMask = saturate(aZ + layerB.z * (1.0 - aZ));
                float  specular     = layerA.w  + layerB.w  * (1.0 - aZ);

                // Convert refraction offset back from gravity-space to screen-UV space
                #if !UNITY_UV_STARTS_AT_TOP
                    refractOff.y = -refractOff.y;
                #endif

                // ── Background wetness ─────────────────────────────────────────
                // Noise flows downward in gravity space → add to dropUV.y
                float2 noiseUV = dropUV * _WetnessScale
                               + float2(0.0, safeTime * _WetnessSpeed);
                float nx = valueNoise(noiseUV)                     * 2.0 - 1.0;
                float ny = valueNoise(noiseUV + float2(5.7, 3.13)) * 2.0 - 1.0;
                float2 wetnessOff = float2(nx, ny) * _WetnessStrength * 0.009;
                // Convert wetness offset to screen-UV space too
                #if !UNITY_UV_STARTS_AT_TOP
                    wetnessOff.y = -wetnessOff.y;
                #endif

                float2 totalOff  = refractOff + wetnessOff * (1.0 - combinedMask);
                float2 refractUV = clamp(screenUV + totalOff, 0.001, 0.999);

                // ── Sample scene ───────────────────────────────────────────────
                float4 scene          = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, screenUV);
                float4 refractedScene = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, refractUV);

                // ── Compose ────────────────────────────────────────────────────
                float3 dropRGB = refractedScene.rgb;
                dropRGB = lerp(dropRGB, _DropColor.rgb, _DropColor.a * combinedMask * 0.3);
                dropRGB += _ReflectionColor.rgb * specular * _ReflectionStrength;

                float3 finalRGB = lerp(scene.rgb, dropRGB, combinedMask * _Transparency);
                finalRGB = lerp(finalRGB, refractedScene.rgb,
                                _WetnessStrength * 0.12 * (1.0 - combinedMask));

                return half4(finalRGB, 1.0);
            }
            ENDHLSL
        }
    }
}
