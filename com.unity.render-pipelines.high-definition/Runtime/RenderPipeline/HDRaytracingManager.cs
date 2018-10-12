using UnityEngine;
using UnityEngine.Rendering;
using System.Collections.Generic;

namespace UnityEngine.Experimental.Rendering.HDPipeline
{
#if ENABLE_RAYTRACING
    public class HDRaytracingManager
    {
        // This class holds everything regarding the state of the ray tracing structure of a sub scene filtered by a layermask
        public class HDRayTracingSubScene
        {
            // The mask that defines which part of the sub-scene is targeted by this
            public LayerMask mask = -1;

            // The native acceleration structure that matches this sub-scene
            public RaytracingAccelerationStructure accelerationStructure = null;

            // The list of renderers in the sub-scene
            public List<Renderer> targetRenderers = null;

            // The list of ray-tracing graphs that reference this sub-scene
            public List<HDRayTracingFilter> referenceFilters = new List<HDRayTracingFilter>();

            // Flag that defines if this sub-scene should be persistent even if there isn't any explicit graph referencing it
            public bool persistent = false;

            // Flag that defines if this sub-scene should be re-evaluated
            public bool obsolete = false;
        }

        // The list of graphs that have been referenced
        List<HDRayTracingFilter> m_Filters = null;

        // The list of sub-scenes that exist
        Dictionary<int, HDRayTracingSubScene> m_SubScenes = null;

        // The list of layer masks that exist
        List<int> m_LayerMasks = null;

        public void RegisterFilter(HDRayTracingFilter targetFilter)
        {
            if(!m_Filters.Contains(targetFilter))
            {
                // Add this graph
                m_Filters.Add(targetFilter);

                // Try to get the sub-scene
                HDRayTracingSubScene currentSubScene = null;
                if (!m_SubScenes.TryGetValue(targetFilter.layermask.value, out currentSubScene))
                {
                    // Create the ray-tracing sub-scene
                    currentSubScene = new HDRayTracingSubScene();
                    currentSubScene.mask = targetFilter.layermask.value;

                    // If this is a new graph, we need to build its data
                    BuildSubSceneStructure(ref currentSubScene);

                    // register this sub-scene and this layer mask
                    m_SubScenes.Add(targetFilter.layermask.value, currentSubScene);
                    m_LayerMasks.Add(targetFilter.layermask.value);
                }

                // Add this graph to the reference graphs
                currentSubScene.referenceFilters.Add(targetFilter);
            }
        }

        public void UnregisterFilter(HDRayTracingFilter targetFilter)
        {
            if (m_Filters.Contains(targetFilter))
            {
                // Add this graph
                m_Filters.Remove(targetFilter);

                // Match the sub-matching sub-scene
                HDRayTracingSubScene currentSubScene = null;
                if (m_SubScenes.TryGetValue(targetFilter.layermask.value, out currentSubScene))
                {
                    // Remove the reference to this graph
                    currentSubScene.referenceFilters.Remove(targetFilter);

                    // Is there is no one referencing this sub-scene and it is not persistent, then we need to delete its
                    if (currentSubScene.referenceFilters.Count == 0 && !currentSubScene.persistent)
                    {
                        // If this is a new graph, we need to build its data
                        DestroySubSceneStructure(ref currentSubScene);

                        // Remove it from the list of the sub-scenes
                        m_SubScenes.Remove(targetFilter.layermask.value);
                        m_LayerMasks.Remove(targetFilter.layermask.value);
                    }
                }
            }
        }

        public void Init(RenderPipelineSettings settings)
        {
            // Create the sub-scenes structure
            m_SubScenes = new Dictionary<int, HDRayTracingSubScene>();

            // The list of masks that are currently requested
            m_LayerMasks = new List<int>();

            // keep track of all the graphs that are to be supported
            m_Filters = new List<HDRayTracingFilter>();

            // Let's start by building the "default" sub-scene (used by the scene camera)
            HDRayTracingSubScene defaultSubScene = new HDRayTracingSubScene();
            defaultSubScene.mask = settings.defaultLayerMask.value;
            defaultSubScene.persistent = true;
            BuildSubSceneStructure(ref defaultSubScene);
            m_SubScenes.Add(settings.defaultLayerMask.value, defaultSubScene);
            m_LayerMasks.Add(settings.defaultLayerMask.value);

            // Grab all the ray-tracing graphs that have been created before
            HDRayTracingFilter[] filterArray = Object.FindObjectsOfType<HDRayTracingFilter>();
            for(int filterIdx = 0; filterIdx < filterArray.Length; ++filterIdx)
            {
                RegisterFilter(filterArray[filterIdx]);
            }
        }

        public void Release()
        {
            for (var subSceneIndex = 0; subSceneIndex < m_LayerMasks.Count; subSceneIndex++)
            {
                HDRayTracingSubScene currentSubScene = m_SubScenes[m_LayerMasks[subSceneIndex]];
                DestroySubSceneStructure(ref currentSubScene);
            }
        }

        public void DestroySubSceneStructure(ref HDRayTracingSubScene subScene)
        {
            if (subScene.accelerationStructure != null)
            {
                for (var i = 0; i < subScene.targetRenderers.Count; i++)
                {
                    if (subScene.targetRenderers[i] != null)
                    {
                        subScene.accelerationStructure.RemoveInstance(subScene.targetRenderers[i]);
                    }
                }
                subScene.accelerationStructure.Dispose();
                subScene.targetRenderers = null;
                subScene.accelerationStructure = null;
            }
        }

        public void UpdateAccelerationStructures()
        {
            // First of all propagate the obsolete flags to the sub scenes
            int numGraphs = m_Filters.Count;
            for(int graphIndex = 0; graphIndex < numGraphs; ++graphIndex)
            {
                // Grab the target graph component
                HDRayTracingFilter filterComponent = m_Filters[graphIndex];
                
                // If this camera had a graph component had an obsolete flag
                if(filterComponent != null && filterComponent.IsObsolete())
                {
                    // Get the sub-scene  that matches
                    HDRayTracingSubScene currentSubScene = null;
                    if (m_SubScenes.TryGetValue(filterComponent.layermask, out currentSubScene))
                    {
                        currentSubScene.obsolete = true;
                    }
                    filterComponent.ResetObsolete();
                }
            }

            // Rebuild all the obsolete scenes
            for (var subSceneIndex = 0; subSceneIndex < m_LayerMasks.Count; subSceneIndex++)
            {
                // Grab the current sub-scene
                HDRayTracingSubScene subScene = m_SubScenes[m_LayerMasks[subSceneIndex]];

                // Does this scene need rebuilding?
                if (subScene.obsolete)
                {
                    DestroySubSceneStructure(ref subScene);
                    BuildSubSceneStructure(ref subScene);
                    subScene.obsolete = false;
                }
            }

            // Update all the transforms
            for (var subSceneIndex = 0; subSceneIndex < m_LayerMasks.Count; subSceneIndex++)
            {
                HDRayTracingSubScene subScene = m_SubScenes[m_LayerMasks[subSceneIndex]];
                if (subScene.accelerationStructure != null)
                {
                    for (var i = 0; i < subScene.targetRenderers.Count; i++)
                    {
                        if (subScene.targetRenderers[i] != null)
                        {
                            subScene.accelerationStructure.TransformInstance(subScene.targetRenderers[i]);
                        }
                    }
                    subScene.accelerationStructure.Build();
                }
            }
        }

        public void BuildSubSceneStructure(ref HDRayTracingSubScene subScene)
        {
            // Destroy the acceleration structure
            subScene.targetRenderers = new List<Renderer>();

            // Create the acceleration structure
            subScene.accelerationStructure = new RaytracingAccelerationStructure();

            // Grab all the renderers from the scene
            var rendererArray = UnityEngine.GameObject.FindObjectsOfType<Renderer>();
            for (var i = 0; i < rendererArray.Length; i++)
            {
                // Convert the object's layer to an int
                int objectLayerValue = 1 << rendererArray[i].gameObject.layer;

                // Is this object in one of the allowed layers ?
                if ((objectLayerValue & subScene.mask.value) != 0)
                {
                    // Add this fella to the renderer list
                    subScene.targetRenderers.Add(rendererArray[i]);
                }
            }

            // If any object build the acceleration structure
            if (subScene.targetRenderers.Count != 0)
            {
                for (var i = 0; i < subScene.targetRenderers.Count; i++)
                {
                    // Add it to the acceleration structure
                    subScene.accelerationStructure.AddInstance(subScene.targetRenderers[i]);
                }
            }

            // build the acceleration structure
            subScene.accelerationStructure.Build();
        }

        public RaytracingAccelerationStructure RequestAccelerationStructure(LayerMask layerMask)
        {
            HDRayTracingSubScene currentSubScene = null;
            if (m_SubScenes.TryGetValue(layerMask.value, out currentSubScene))
            {
                return currentSubScene.accelerationStructure;
            }
            return null;
        }
    }
#endif
}
