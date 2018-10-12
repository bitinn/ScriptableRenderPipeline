using UnityEngine;
using UnityEngine.Rendering;
using System.Collections.Generic;

namespace UnityEngine.Experimental.Rendering.HDPipeline
{
#if ENABLE_RAYTRACING
    public class HDRaytracingReflections
    {
        HDRenderPipelineAsset m_PipelineAsset = null;

        SkyManager m_SkyManager = null;
        HDRaytracingManager m_RaytracingManager = null;
        SharedRTManager m_SharedRTManager = null;

        // Raytracing data
        const float m_RayBias = 0.0001f;
        const float m_RayMaxLength = 1000.0f;

        // String values
        const string m_RayGenShaderName = "RayGenReflections";
        const string m_MissShaderName = "MissShaderReflections";
        const string m_RaytracingAccelerationStructureName = "_RaytracingAccelerationStructure";
        public static readonly int m_RayBiasName = Shader.PropertyToID("_RayBias");
        public static readonly int _RayMaxLengthName = Shader.PropertyToID("_RayMaxLength");

        public HDRaytracingReflections()
        {
        }

        public void Init(HDRenderPipelineAsset asset, SkyManager skyManager, HDRaytracingManager raytracingManager, SharedRTManager sharedRTManager)
        {
            // Keep track of the pipeline asset
            m_PipelineAsset = asset;

            // Keep track of the sky manager
            m_SkyManager = skyManager;

            // keep track of the ray tracing manager
            m_RaytracingManager = raytracingManager;

            // Keep track of the shared rt manager
            m_SharedRTManager = sharedRTManager;
        }

        public void Release()
        {
        }

        public void RenderReflections(HDCamera hdCamera, CommandBuffer cmd, RTHandleSystem.RTHandle outputTexture)
        {
            // If no reflection shader is available, just skip right away
            if (m_PipelineAsset.renderPipelineResources.shaders.reflectionRaytracing == null) return;
            RaytracingShader reflectionShader = m_PipelineAsset.renderPipelineResources.shaders.reflectionRaytracing;

            // Try to grab the acceleration structure for the target camera
            HDRayTracingFilter raytracingFilter = hdCamera.camera.gameObject.GetComponent<HDRayTracingFilter>();
            RaytracingAccelerationStructure accelerationStructure = null;
            if (raytracingFilter != null)
            {
                accelerationStructure = m_RaytracingManager.RequestAccelerationStructure(raytracingFilter.layermask);
            }
            else if(hdCamera.camera.cameraType == CameraType.SceneView || hdCamera.camera.cameraType == CameraType.Preview)
            {
                // For the scene view, we want to use the default acceleration structure
                accelerationStructure = m_RaytracingManager.RequestAccelerationStructure(m_PipelineAsset.renderPipelineSettings.defaultLayerMask);
            }

            // If no acceleration structure available, end it now
            if(accelerationStructure == null) return;

            // Set the acceleration structure for the pass
            cmd.SetRaytracingAccelerationStructure(reflectionShader, m_RaytracingAccelerationStructureName, accelerationStructure);

            // Define the shader pass to use for the reflection pass
            cmd.SetRaytracingShaderPass(reflectionShader, "RTRaytrace_Reflections");

            // Set the data for the ray generation
            cmd.SetRaytracingTextureParam(reflectionShader, m_RayGenShaderName, HDShaderIDs._SsrLightingTextureRW, outputTexture);
            cmd.SetRaytracingTextureParam(reflectionShader, m_RayGenShaderName, HDShaderIDs._DepthTexture, m_SharedRTManager.GetDepthStencilBuffer());
            cmd.SetRaytracingTextureParam(reflectionShader, m_RayGenShaderName, HDShaderIDs._NormalBufferTexture, m_SharedRTManager.GetNormalBuffer());
            cmd.SetRaytracingFloatParams(reflectionShader, m_RayBiasName, m_RayBias);
            cmd.SetRaytracingFloatParams(reflectionShader, _RayMaxLengthName, m_RayMaxLength);

            // Set the data for the ray miss
            cmd.SetRaytracingTextureParam(reflectionShader, m_MissShaderName, HDShaderIDs._SkyTexture, m_SkyManager.skyReflection);

            // Run the calculus
            cmd.DispatchRays(reflectionShader, m_RayGenShaderName, (uint)hdCamera.actualWidth, (uint)hdCamera.actualHeight);
        }
    }
#endif
}
