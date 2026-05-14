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

        // Fullscreen render feature pattern — manual composite against _BlitTexture.
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

            // Smooth value noise for wetness background distortion
            float valueNoise(float2 uv)
            {
                float2 i = floor(uv);
                float2 f = frac(uv);
                float2 u = f * f * (3.0 - 2.0 * f);   // smoothstep curve

                float a = hash1(i);
                float b = hash1(i + float2(1.0, 0.0));
                float c = hash1(i + float2(0.0, 1.0));
                float d = hash1(i + float2(1.0, 1.0));

                return lerp(lerp(a, b, u.x), lerp(c, d, u.x), u.y);
            }

            // ── Single raindrop grid layer ─────────────────────────────────────
            // Returns:
            //   .xy  = refraction UV offset in screen-UV space
            //   .z   = combined opacity mask  [0,1]
            //   .w   = specular highlight     [0,1]
            float4 RaindropLayer(
                float2 screenUV,
                float  aspect,
                float  safeTime,
                float  density,
                float  speedMult,
                float  sizeMult)
            {
                // Grid: cols ≈ density * aspect so cells are approximately square in pixels
                float cols       = max(1.0, round(density * aspect));
                float rows       = density;
                // Cell pixel aspect ratio: how many horizontal pixels per vertical pixel in a cell
                float cellAspect = (aspect * rows) / cols;

                float2 gridUV = float2(screenUV.x * cols, screenUV.y * rows);
                float2 cellID = floor(gridUV);
                float2 cellUV = frac(gridUV);           // [0,1] within this cell

                // Per-cell randomisation
                float2 rnd  = hash2(cellID);
                float  rnd1 = hash1(cellID + float2(3.7, 1.3));
                float  rnd2 = hash1(cellID + float2(8.1, 4.6));

                // X position: random but kept away from cell edges [0.15, 0.85]
                float dropX = 0.15 + rnd.x * 0.70;

                // Fall speed with per-drop variance
                float speed = speedMult * max(0.05,
                              1.0 - _SpeedVariance * 0.5 + _SpeedVariance * rnd.y);

                // Y: increases over time (0=top, 1=bottom), wraps around
                float dropY = frac(safeTime * speed * 0.1 + rnd1);

                // Horizontal drift from wind (varies per drop via rnd2)
                float dropXt = saturate(dropX + _WindStrength * dropY * 0.12 * (rnd2 * 2.0 - 1.0));

                // ── Drop SDF (circular in screen pixel space) ──────────────────
                float2 dropCenter = float2(dropXt, dropY);
                float2 d          = cellUV - dropCenter;
                d.x               *= cellAspect;        // correct for non-square cells
                float dropDist    = length(d);

                float radius   = _DropSize * sizeMult;
                float dropMask = 1.0 - smoothstep(radius - 0.018, radius + 0.018, dropDist);

                // ── Trail SDF (wet streak above the drop) ─────────────────────
                // In screen UV: y=0 is top, y=1 is bottom.
                // "Above" the drop means cellUV.y < dropY.
                float trailHalfW = radius * _TrailWidth / max(cellAspect, 0.001);
                float above      = dropY - cellUV.y;    // > 0 when pixel is above drop
                float trailMask  = 0.0;
                if (above > 0.001 && above < _TrailLength
                    && abs(cellUV.x - dropXt) < trailHalfW)
                {
                    float xFade  = 1.0 - abs(cellUV.x - dropXt) / max(trailHalfW, 0.001);
                    float yFade  = 1.0 - above / _TrailLength;
                    trailMask    = saturate(xFade * yFade) * _TrailOpacity;
                }

                // ── Surface normal from drop SDF ───────────────────────────────
                // Points outward from the drop centre (in screen-UV-corrected space)
                float2 normal2D = float2(d.x / max(cellAspect, 0.001), d.y)
                                  / max(dropDist, 0.001);

                // ── Refraction offset ──────────────────────────────────────────
                // Convex lens: bend inward → negate normal
                float2 refractOff  = -normal2D * dropMask   * _RefractionStrength * 0.045;
                // Trail: tiny horizontal wobble simulating thin water film
                refractOff        += float2((rnd.x - 0.5) * 0.004, 0.0) * trailMask;

                // ── Specular / reflection highlight ────────────────────────────
                // Directional light from top-left of the window
                float2 lightDir = normalize(float2(-0.4, -0.7));
                float  spec     = pow(saturate(dot(-normal2D, lightDir)),
                                       max(_ReflectionSharpness, 1.0)) * dropMask;

                float combinedMask = saturate(dropMask + trailMask * (1.0 - dropMask));

                return float4(refractOff, combinedMask, spec);
            }

            half4 frag(Varyings IN) : SV_Target
            {
                float2 screenUV = IN.texcoord;

                // Guard: _ScreenParams can be (1,1) during early blit passes
                float screenW = _ScreenParams.x;
                float screenH = _ScreenParams.y;
                if (screenW < 2.0 || screenH < 2.0)
                    return SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, screenUV);

                float aspect   = screenW / screenH;
                float safeTime = fmod(_Time.y, 3600.0);

                // ── Two raindrop layers for depth and variety ──────────────────
                // Layer A: large, slow, sparse primary drops
                float4 layerA = RaindropLayer(
                    screenUV, aspect, safeTime,
                    _DropDensity,            // density
                    _DropSpeed,              // speed
                    1.0);                    // size multiplier

                // Layer B: small, faster, denser secondary drops
                // Time offset (17.3) breaks synchronisation with layer A
                float4 layerB = RaindropLayer(
                    screenUV, aspect, safeTime + 17.3,
                    _DropDensity * 1.75,     // denser
                    _DropSpeed   * 1.55,     // faster
                    0.55);                   // smaller

                // Composite layers: B underneath, A on top
                float  aZ    = layerA.z;
                float  bZ    = layerB.z * (1.0 - aZ);
                float2 refractOffset = layerA.xy + layerB.xy * (1.0 - aZ);
                float  combinedMask  = saturate(aZ + bZ);
                float  specular      = layerA.w + layerB.w * (1.0 - aZ);

                // ── Background wetness: noise-based UV distortion ──────────────
                // Simulates overall wet glass surface between drops
                float2 noiseUV = screenUV * _WetnessScale
                               + float2(0.0, safeTime * _WetnessSpeed);
                float nx = valueNoise(noiseUV)                      * 2.0 - 1.0;
                float ny = valueNoise(noiseUV + float2(5.7, 3.13))  * 2.0 - 1.0;
                float2 wetnessOffset = float2(nx, ny) * _WetnessStrength * 0.009;

                // Wetness only visible outside drop areas (drops override it)
                float2 totalOffset = refractOffset
                                   + wetnessOffset * (1.0 - combinedMask);
                float2 refractUV   = clamp(screenUV + totalOffset, 0.001, 0.999);

                // ── Sample scene ───────────────────────────────────────────────
                float4 scene          = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, screenUV);
                float4 refractedScene = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, refractUV);

                // ── Compose drop colour ────────────────────────────────────────
                // Start with refracted scene inside drops
                float3 dropRGB = refractedScene.rgb;

                // Tint the drop slightly with _DropColor (alpha controls tint strength)
                dropRGB = lerp(dropRGB, _DropColor.rgb,
                               _DropColor.a * combinedMask * 0.3);

                // Add specular reflection highlight
                dropRGB += _ReflectionColor.rgb * specular * _ReflectionStrength;

                // ── Blend drops over scene ─────────────────────────────────────
                float3 finalRGB = lerp(scene.rgb, dropRGB, combinedMask * _Transparency);

                // Subtle wetness tint over the whole frame (between drops)
                finalRGB = lerp(finalRGB, refractedScene.rgb,
                                _WetnessStrength * 0.12 * (1.0 - combinedMask));

                return half4(finalRGB, 1.0);
            }
            ENDHLSL
        }
    }
}
