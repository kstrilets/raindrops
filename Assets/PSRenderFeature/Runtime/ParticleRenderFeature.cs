using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Rendering.Universal;

public class ParticleRendererFeature : ScriptableRendererFeature
{
    public ParticleRenderPass pass;

    public override void Create()
    {
        pass = new ParticleRenderPass();
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if (pass != null) renderer.EnqueuePass(pass);
    }
}

public class ParticleRenderPass : ScriptableRenderPass
{
    public ParticleRenderPass()
    {
        renderPassEvent = RenderPassEvent.AfterRenderingTransparents;
    }

    class ParticlePassData
    {
        public Material material;
        public Mesh mesh;
        public int particleCount;
        public GraphicsBuffer particleBuffer;
        public Vector3 objPosition;
        public Vector3 objScale;
    }

    class ParticleComputePassData
    {
        public ComputeShader compute;
        public int kernel;
        public int particleCount;
        public float time;
        public float deltaTime;
        public int dispatchGroupsX;
        public BufferHandle particleBuffer;
    }

    public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
    {
        var controller = ParticleController.Active;
        if (controller == null || controller.Compute == null) return;
        if (controller.Material == null || controller.Mesh == null || controller.ParticleBuffer == null) return;
        if (controller.ParticleCount <= 0 || controller.DispatchGroupsX <= 0) return;

        var particleBuffer = renderGraph.ImportBuffer(controller.ParticleBuffer);
        bool simulateThisFrame = controller.TryGetSimulationStep(out float simulationDeltaTime);

        if (simulateThisFrame)
        {
            using (var builder = renderGraph.AddComputePass<ParticleComputePassData>("Particle System Compute", out var passData))
            {
                builder.UseBuffer(particleBuffer, AccessFlags.ReadWrite);

                passData.compute = controller.Compute;
                passData.kernel = controller.Kernel;
                passData.particleCount = controller.ParticleCount;
                passData.time = Time.time;
                passData.deltaTime = simulationDeltaTime;
                passData.dispatchGroupsX = controller.DispatchGroupsX;
                passData.particleBuffer = particleBuffer;

                builder.SetRenderFunc((ParticleComputePassData data, ComputeGraphContext cgContext) => {
                    cgContext.cmd.SetComputeIntParam(data.compute, "_ParticleCount", data.particleCount);
                    cgContext.cmd.SetComputeFloatParam(data.compute, "t", data.time);
                    cgContext.cmd.SetComputeFloatParam(data.compute, "dt", data.deltaTime);
                    cgContext.cmd.SetComputeBufferParam(data.compute, data.kernel, "Result", data.particleBuffer);
                    cgContext.cmd.DispatchCompute(data.compute, data.kernel, data.dispatchGroupsX, 1, 1);
                });
            }
        }

        using (var builder = renderGraph.AddRasterRenderPass<ParticlePassData>("Particle System Draw", out var passData))
        {
            var resourceData = frameData.Get<UniversalResourceData>();
            builder.SetRenderAttachment(resourceData.activeColorTexture, 0, AccessFlags.Write);
            builder.UseBuffer(particleBuffer, AccessFlags.Read);

            passData.material = controller.Material;
            passData.mesh = controller.Mesh;
            passData.particleCount = controller.ParticleCount;
            passData.particleBuffer = controller.ParticleBuffer;
            passData.objPosition = controller.transform.position;
            passData.objScale = controller.transform.localScale;

            builder.SetRenderFunc((ParticlePassData data, RasterGraphContext rgContext) => {
                data.material.SetBuffer("Result", data.particleBuffer);
                data.material.SetVector("_ObjPos", data.objPosition);
                data.material.SetVector("_ObjScale", data.objScale);
                rgContext.cmd.DrawMeshInstancedProcedural(data.mesh, 0, data.material, 0, data.particleCount, null);
            });
        }
        ;
    }
}