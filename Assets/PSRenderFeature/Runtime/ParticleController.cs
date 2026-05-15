using UnityEngine;

public class ParticleController : MonoBehaviour
{
    [SerializeField] ComputeShader compute;
    [SerializeField] Mesh mesh;
    [SerializeField] Material material;
    [SerializeField] int particleCount = 10000;
    [SerializeField] float areaSize = 10f;
    [SerializeField] float spawnDistanceFromCamera = 8f;

    public struct Particle
    {
        public Vector3 position;
        public Vector3 velocity;
    }

    GraphicsBuffer particleBuffer;
    int kCSMain;
    uint threadGroupSizeX = 256;
    int lastSimulationFrame = -1;

    // Public access for the Render Pass
    public ComputeShader Compute => compute;
    public int Kernel => kCSMain;
    public int DispatchGroupsX => Mathf.CeilToInt(particleCount / (float)Mathf.Max(1u, threadGroupSizeX));
    public Material Material => material;
    public Mesh Mesh => mesh;
    public GraphicsBuffer ParticleBuffer => particleBuffer;
    public int ParticleCount => particleCount;
    public float AreaSize => areaSize;

    public bool TryGetSimulationStep(out float deltaTime)
    {
        if (lastSimulationFrame == Time.frameCount)
        {
            deltaTime = 0f;
            return false;
        }

        lastSimulationFrame = Time.frameCount;
        deltaTime = Time.deltaTime;
        return true;
    }

    protected void Start()
    {
        transform.position = Camera.main.transform.position + Camera.main.transform.forward * spawnDistanceFromCamera;
        if (compute == null) return;
        kCSMain = compute.FindKernel("CSMain");
        compute.GetKernelThreadGroupSizes(kCSMain, out threadGroupSizeX, out _, out _);
        InitializeBuffers();
    }

    protected void OnDestroy() => particleBuffer?.Release();

    void InitializeBuffers()
    {
        particleBuffer = new GraphicsBuffer(GraphicsBuffer.Target.Structured, particleCount, sizeof(float) * 6);

        Particle[] data = new Particle[particleCount];

        for (int i = 0; i < particleCount; i++)
        {
            data[i].position = Random.insideUnitSphere * 3f;
            data[i].velocity = Random.insideUnitSphere;
        }

        particleBuffer.SetData(data);
    }

    public static ParticleController Active { get; private set; }

    protected void OnEnable()
    {
        Active = this;
    }

    protected void OnDisable()
    {
        if (Active == this) Active = null;
    }
}