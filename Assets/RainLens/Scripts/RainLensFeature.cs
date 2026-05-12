using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Rendering.RenderGraphModule.Util;

public class RainLensFeature : ScriptableRendererFeature
{
    [System.Serializable]
    public class Settings
    {
        public Material material;
        public RenderPassEvent passEvent = RenderPassEvent.BeforeRenderingPostProcessing;
    }

    private class RainLensPass : ScriptableRenderPass
    {
        private readonly string _passName;
        private Material _material;

        public RainLensPass(RenderPassEvent passEvent, string passName)
        {
            renderPassEvent = passEvent;
            _passName = passName;
            requiresIntermediateTexture = true;
        }

        public void Setup(Material material)
        {
            _material = material;
        }

        public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
        {
            if (_material == null)
            {
                return;
            }

            UniversalResourceData resourceData = frameData.Get<UniversalResourceData>();
            if (resourceData.isActiveTargetBackBuffer)
            {
                return;
            }

            UniversalCameraData cameraData = frameData.Get<UniversalCameraData>();
            RenderTextureDescriptor descriptor = cameraData.cameraTargetDescriptor;
            descriptor.depthBufferBits = 0;

            TextureHandle source = resourceData.activeColorTexture;
            TextureHandle destination = UniversalRenderer.CreateRenderGraphTexture(renderGraph, descriptor, "_RainLensTempColor", false);

            var blitParameters = new RenderGraphUtils.BlitMaterialParameters(source, destination, _material, 0);
            renderGraph.AddBlitPass(blitParameters, _passName);
            renderGraph.AddCopyPass(destination, source, _passName + " Copy");
        }
    }

    public Settings settings = new Settings();

    private RainLensPass _pass;

    public override void Create()
    {
        _pass = new RainLensPass(settings.passEvent, "RainLens Pass");
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if (settings.material == null)
        {
            return;
        }

        if (renderingData.cameraData.isSceneViewCamera)
        {
            return;
        }

        _pass.renderPassEvent = settings.passEvent;
        _pass.Setup(settings.material);
        renderer.EnqueuePass(_pass);
    }
}
