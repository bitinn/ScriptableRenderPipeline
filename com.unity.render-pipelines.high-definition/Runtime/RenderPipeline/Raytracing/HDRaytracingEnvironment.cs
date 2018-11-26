using UnityEngine;
using UnityEngine.Rendering;
using System.Collections.Generic;
using Unity.Collections;

namespace UnityEngine.Experimental.Rendering.HDPipeline
{
    [DisallowMultipleComponent, ExecuteInEditMode]
    public class HDRaytracingEnvironment : MonoBehaviour
    {
#if ENABLE_RAYTRACING
        // Generic Ray Data
        public float rayBias = 0.001f;
        public float rayMaxLength = 1000f;

        // Area Shadow Data
        [Range(1, 20)]
        public int denoiseRadius = 10;
        [Range(0.01f, 20.0f)]
        public float denoiseSigma = 5.0f;

        // Area light budget
        public const int maxAreaLightShadows = 4;
        [Range(0, maxAreaLightShadows - 1)]
        public int numAreaLightShadows = 1;

        // Light Cluster Dimensions
        [Range(0, 20)]
        public int maxNumLightsPercell = 10;
        [Range(0.01f, 100.0f)]
        public float cameraClusterRange = 10;

        void Start()
        {
            // Grab the High Definition RP
            HDRenderPipeline hdPipeline = RenderPipelineManager.currentPipeline as HDRenderPipeline;
            if (hdPipeline != null)
            {
                hdPipeline.m_RayTracingManager.RegisterEnvironment(this);
            }
        }
        void OnDestroy()
        {
            // Grab the High Definition RP
            HDRenderPipeline hdPipeline = RenderPipelineManager.currentPipeline as HDRenderPipeline;
            if (hdPipeline != null)
            {
                hdPipeline.m_RayTracingManager.UnregisterEnvironment(this);
            }
        }
#endif
    }
}
