using UnityEngine;
using UnityEngine.Rendering;
using System.Collections.Generic;

namespace UnityEngine.Experimental.Rendering.HDPipeline
{
#if ENABLE_RAYTRACING
    public class HDRaytracingReflections
    {
        // External structures
        HDRenderPipelineAsset m_PipelineAsset = null;
        SkyManager m_SkyManager = null;
        HDRaytracingManager m_RaytracingManager = null;
        SharedRTManager m_SharedRTManager = null;

        // The target denoising kernel
        static int m_KernelFilter;

        // Intermediate buffer that stores the reflection pre-denoising
        RTHandleSystem.RTHandle m_IntermediateBuffer = null;

        // Light cluster structure
        public HDRaytracingLightCluster m_LightCluster = null;

        // String values
        const string m_RayGenShaderName = "RayGenReflections";
        const string m_MissShaderName = "MissShaderReflections";
        const string m_ClosestHitShaderName = "ClosestHitMain";

        // Shader Identifiers
        public static readonly int _DenoiseRadius = Shader.PropertyToID("_DenoiseRadius");
        public static readonly int _GaussianSigma = Shader.PropertyToID("_GaussianSigma");

        public static readonly int _RaytracingLightCluster = Shader.PropertyToID("_RaytracingLightCluster");
        public static readonly int _MinClusterPos = Shader.PropertyToID("_MinClusterPos");
        public static readonly int _MaxClusterPos = Shader.PropertyToID("_MaxClusterPos");
        public static readonly int _LightPerCellCount = Shader.PropertyToID("_LightPerCellCount");
        public static readonly int _LightDatasRT = Shader.PropertyToID("_LightDatasRT");
        public static readonly int _PunctualLightCountRT = Shader.PropertyToID("_PunctualLightCountRT");
        public static readonly int _AreaLightCountRT = Shader.PropertyToID("_AreaLightCountRT");
        public static readonly int _PixelSpreadAngle = Shader.PropertyToID("_PixelSpreadAngle");

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

            m_IntermediateBuffer = RTHandles.Alloc(Vector2.one, filterMode: FilterMode.Point, colorFormat: RenderTextureFormat.ARGBHalf, sRGB: false, enableRandomWrite: true, useMipMap: false, name: "IntermediateReflectionBuffer");

            // Allocate the light cluster
            m_LightCluster = new HDRaytracingLightCluster();
            m_LightCluster.Initialize(asset, raytracingManager);

        }

        public void Release()
        {
            m_LightCluster.ReleaseResources();
            m_LightCluster = null;

            RTHandles.Release(m_IntermediateBuffer);
        }

        public void RenderReflections(HDCamera hdCamera, CommandBuffer cmd, RTHandleSystem.RTHandle outputTexture, ScriptableRenderContext renderContext)
        {
            // First thing to check is: Do we have a valid ray-tracing environment?
            HDRaytracingEnvironment rtEnvironement = m_RaytracingManager.CurrentEnvironment();
            Texture2DArray noiseTexture = m_RaytracingManager.m_RGNoiseTexture;
            ComputeShader bilateralFilter = m_PipelineAsset.renderPipelineResources.shaders.reflectionBilateralFilterCS;
            RaytracingShader reflectionShader = m_PipelineAsset.renderPipelineResources.shaders.reflectionRaytracing;
            if (rtEnvironement == null || noiseTexture == null || bilateralFilter == null || reflectionShader == null)
            {
                return;
            }

            // If no reflection shader is available, just skip right away
            if (m_PipelineAsset.renderPipelineResources.shaders.reflectionRaytracing == null) return;
            m_KernelFilter = bilateralFilter.FindKernel("GaussianBilateralFilter");

            // Try to grab the acceleration structure for the target camera
            HDRayTracingFilter raytracingFilter = hdCamera.camera.gameObject.GetComponent<HDRayTracingFilter>();
            RaytracingAccelerationStructure accelerationStructure = null;
            List<HDAdditionalLightData> lightData = null;
            if (raytracingFilter != null)
            {
                accelerationStructure = m_RaytracingManager.RequestAccelerationStructure(raytracingFilter.layermask);
                lightData = m_RaytracingManager.RequestHDLightList(raytracingFilter.layermask);
            }
            else if(hdCamera.camera.cameraType == CameraType.SceneView || hdCamera.camera.cameraType == CameraType.Preview)
            {
                // For the scene view, we want to use the default acceleration structure
                accelerationStructure = m_RaytracingManager.RequestAccelerationStructure(m_PipelineAsset.renderPipelineSettings.defaultLayerMask);
                lightData = m_RaytracingManager.RequestHDLightList(m_PipelineAsset.renderPipelineSettings.defaultLayerMask);
            }

            // If no acceleration structure available, end it now
            if (accelerationStructure == null) return;

            // Evaluate the light cluster
            m_LightCluster.EvaluateLightClusters(cmd, hdCamera, lightData);

            // Define the shader pass to use for the reflection pass
            cmd.SetRaytracingShaderPass(reflectionShader, "RTRaytrace_Reflections");

            // Set the acceleration structure for the pass
            cmd.SetRaytracingAccelerationStructure(reflectionShader, HDShaderIDs._RaytracingAccelerationStructureName, accelerationStructure);

            // Inject the ray-tracing noise data
            cmd.SetRaytracingTextureParam(reflectionShader, m_RayGenShaderName, HDShaderIDs._RaytracingNoiseTexture, noiseTexture);
            cmd.SetRaytracingIntParams(reflectionShader, HDShaderIDs._RaytracingNoiseResolution, noiseTexture.width);
            cmd.SetRaytracingIntParams(reflectionShader, HDShaderIDs._RaytracingNumNoiseLayers, noiseTexture.depth);

            // Inject the ray generation data
            cmd.SetRaytracingFloatParams(reflectionShader, HDShaderIDs._RaytracingRayBias, rtEnvironement.rayBias);
            cmd.SetRaytracingFloatParams(reflectionShader, HDShaderIDs._RaytracingRayMaxLength, rtEnvironement.rayMaxLength);

            // Set the data for the ray generation
            cmd.SetRaytracingTextureParam(reflectionShader, m_RayGenShaderName, HDShaderIDs._SsrLightingTextureRW, m_IntermediateBuffer);
            cmd.SetRaytracingTextureParam(reflectionShader, m_RayGenShaderName, HDShaderIDs._DepthTexture, m_SharedRTManager.GetDepthStencilBuffer());
            cmd.SetRaytracingTextureParam(reflectionShader, m_RayGenShaderName, HDShaderIDs._NormalBufferTexture, m_SharedRTManager.GetNormalBuffer());

            // Compute the pixel spread value
            float pixelSpreadAngle = Mathf.Atan(2.0f * Mathf.Tan(hdCamera.camera.fieldOfView * Mathf.PI / 360.0f) / Mathf.Min(hdCamera.actualWidth, hdCamera.actualHeight));
            cmd.SetRaytracingFloatParam(reflectionShader, _PixelSpreadAngle, pixelSpreadAngle);

            // LightLoop data
            cmd.SetGlobalBuffer(_RaytracingLightCluster, m_LightCluster.GetCluster());
            cmd.SetGlobalBuffer(_LightDatasRT, m_LightCluster.GetLightDatas());
            cmd.SetGlobalVector(_MinClusterPos, m_LightCluster.GetMinClusterPos());
            cmd.SetGlobalVector(_MaxClusterPos, m_LightCluster.GetMaxClusterPos());
            cmd.SetGlobalInt(_LightPerCellCount, rtEnvironement.maxNumLightsPercell);
            cmd.SetGlobalInt(_PunctualLightCountRT, m_LightCluster.GetPunctualLightCount());
            cmd.SetGlobalInt(_AreaLightCountRT, m_LightCluster.GetAreaLightCount());

            // Set the data for the ray miss
            cmd.SetRaytracingTextureParam(reflectionShader, m_MissShaderName, HDShaderIDs._SkyTexture, m_SkyManager.skyReflection);

            // Run the calculus
            cmd.DispatchRays(reflectionShader, m_RayGenShaderName, (uint)hdCamera.actualWidth, (uint)hdCamera.actualHeight);

            using (new ProfilingSample(cmd, "Filter Reflection", CustomSamplerId.Raytracing.GetSampler()))
            {
                // Inject all the parameters for the compute
                cmd.SetComputeIntParam(bilateralFilter, _DenoiseRadius, rtEnvironement.denoiseRadius);
                cmd.SetComputeFloatParam(bilateralFilter, _GaussianSigma, rtEnvironement.denoiseSigma);
                cmd.SetComputeTextureParam(bilateralFilter, m_KernelFilter, "_SourceTexture", m_IntermediateBuffer);
                cmd.SetComputeTextureParam(bilateralFilter, m_KernelFilter, HDShaderIDs._DepthTexture, m_SharedRTManager.GetDepthStencilBuffer());
                cmd.SetComputeTextureParam(bilateralFilter, m_KernelFilter, HDShaderIDs._NormalBufferTexture, m_SharedRTManager.GetNormalBuffer());

                // Set the output slot
                cmd.SetComputeTextureParam(bilateralFilter, m_KernelFilter, "_OutputTexture", outputTexture);

                // Texture dimensions
                int texWidth = outputTexture.rt.width;
                int texHeight = outputTexture.rt.width;

                // Evaluate the dispatch parameters
                int areaTileSize = 8;
                int numTilesX = (texWidth + (areaTileSize - 1)) / areaTileSize;
                int numTilesY = (texHeight + (areaTileSize - 1)) / areaTileSize;

                // Compute the texture
                cmd.DispatchCompute(bilateralFilter, m_KernelFilter, numTilesX, numTilesY, 1);
            }
        }
    }
#endif
}
