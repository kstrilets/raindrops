# Morphing Blend Shaders

Four shaders demonstrating texture morphing techniques. All expect RGBA textures
with the RainDropNormalMap channel layout (R=normalX, G=normalY, B=mask, A=trail).

| Shader | Technique | Extra assets needed |
|---|---|---|
| MorphDissolve | Noise threshold dissolve with edge rim | Noise texture |
| MorphOpticalFlow | Flow-warped cross-fade | None |
| MorphHeightPriority | Height-field driven blend | None |
| MorphFlowPriority | **Combined** flow warp + height priority | None — recommended |

## Controls shared by all shaders
- `_BlendT` — 0 = fully Texture A, 1 = fully Texture B
- `_BlendSharpness` — how gradual the transition boundary is

## MorphDissolve specific
- `_NoiseTex` — any tileable noise / Perlin texture
- `_Threshold` — maps directly to `_BlendT` conceptually
- `_EdgeWidth` / `_EdgeBrightness` / `_EdgeColor` — rim light at the boundary

## MorphOpticalFlow
- `_WarpStrength` — how far pixels push during the transition (0.05–0.12 recommended)
- `_BlendSharpness` — how wide the cross-fade window is around t=0.5

## MorphHeightPriority
- `_BlendSharpness` — small = gradual sweep, large = sharp local boundary
- Transition always starts at low-height regions (trail) and ends at the dome peak

## MorphFlowPriority (recommended)
- `_WarpStrength` — how far pixels push during the transition
- `_FlowInfluence` — how much the normal map drives the warp vs straight blend
- `_BlendSharpness` — controls local boundary crispness
- Warp peaks at the midpoint of the transition and fades at both ends
