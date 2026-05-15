Shader"Custom/ParticleSim3DRender"
{
    Properties
    {
        _FastColor("Fast Particle Color", Color) = (1, 0, 0, 1)
        _SlowColor("Slow Particle Color", Color) = (0, 0.5, 1, 1)
        _Intensity("Lightning Intensity", Float) = 7
        _Scale("Particle Scale", Float) = 0.4
    }

    SubShader
    {
        Tags 
        { 
            "RenderType" = "Transparent" 
            "RenderPipeline" = "UniversalPipeline" 
            "Queue" = "Transparent" 
        }
        
Blend One One
        ZWrite Off
        Cull Off

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 4.5

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

struct Particle
{
    float3 position;
    float3 velocity;
};

struct Attributes
{
    float4 positionOS : POSITION;
    uint instanceID : SV_InstanceID;
};

struct Varyings
{
    float4 position : SV_POSITION;
    float4 color : COLOR;
};

            // Particle data from Compute Shader
StructuredBuffer<Particle> Result;

            CBUFFER_START(UnityPerMaterial)
half4 _FastColor;
half4 _SlowColor;
float _Intensity;
float _Scale;
float3 _ObjPos; // World position of the container object
float3 _ObjScale; // Scale of the container object
CBUFFER_END

            Varyings vert(
Attributes IN)
            {
Varyings OUT;
                
Particle p = Result[IN.instanceID];
                
                // Transform particle position from local simulation space to world space
float3 localPos = IN.positionOS.xyz * 0.1 * _Scale;
float3 worldPos = localPos * _ObjScale + p.position + _ObjPos;

                OUT.position = TransformWorldToHClip(worldPos);

                // Color based on velocity
                OUT.color = lerp(_SlowColor, _FastColor, length(p.velocity) * 0.5);

                return
OUT;
            }

half4 frag(Varyings IN) : SV_Target
{
    return half4(IN.color.xyz * _Intensity, 1.0);
}
            ENDHLSL
        }
    }
}