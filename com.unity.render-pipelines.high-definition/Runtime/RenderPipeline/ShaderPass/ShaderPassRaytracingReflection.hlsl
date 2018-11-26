

void UpdateLightingHierarchyWeights(inout float hierarchyWeight, inout float weight)
{
    float accumulatedWeight = hierarchyWeight + weight;
    hierarchyWeight = saturate(accumulatedWeight);
    weight -= saturate(accumulatedWeight - hierarchyWeight);
}

#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/ImageBasedLighting.hlsl"
#include "Packages/com.unity.render-pipelines.core\ShaderLibrary\AreaLighting.hlsl"
#include "Packages/com.unity.render-pipelines.high-definition/Runtime/Material/LTCAreaLight/LTCAreaLight.hlsl"
#include "Packages/com.unity.render-pipelines.high-definition/Runtime/Material/PreIntegratedFGD/PreIntegratedFGD.hlsl"
#include "Packages/com.unity.render-pipelines.high-definition\Runtime\Lighting\LightLoop\HDShadow.hlsl"
#include "Packages/com.unity.render-pipelines.core\ShaderLibrary\Color.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/VolumeRendering.hlsl"
#include "Packages/com.unity.render-pipelines.high-definition\Runtime\Lighting\LightLoop\LightLoopDef.hlsl"

// Lit Specific includes
#define CLEAR_COAT_IOR 1.5
#define CLEAR_COAT_IETA (1.0 / CLEAR_COAT_IOR) // IETA is the inverse eta which is the ratio of IOR of two interface
#define CLEAR_COAT_F0 0.04 // IORToFresnel0(CLEAR_COAT_IOR)
#define CLEAR_COAT_ROUGHNESS 0.03
#define CLEAR_COAT_PERCEPTUAL_SMOOTHNESS RoughnessToPerceptualSmoothness(CLEAR_COAT_ROUGHNESS)
#define CLEAR_COAT_PERCEPTUAL_ROUGHNESS RoughnessToPerceptualRoughness(CLEAR_COAT_ROUGHNESS)
#define MATERIAL_INCLUDE_SUBSURFACESCATTERING
#define MATERIAL_INCLUDE_TRANSMISSION
#include "Packages/com.unity.render-pipelines.high-definition\Runtime\Material\SubsurfaceScattering\SubsurfaceScattering.hlsl"
#include "Packages/com.unity.render-pipelines.high-definition/Runtime/Material/Lit/LitSurfaceToBSDF.hlsl"
#include "Packages/com.unity.render-pipelines.high-definition/Runtime/Material/Lit/LitPreLightData.hlsl"
#define HAS_LIGHTLOOP
#include "Packages/com.unity.render-pipelines.high-definition/Runtime/Material/Lit/LitBSDF.hlsl"

#include "Packages/com.unity.render-pipelines.high-definition/Runtime/RenderPipeline/Raytracing/Shaders/RaytracingLightLoop.hlsl"

// Generic function that handles the reflection code
[shader("closesthit")]
void ClosestHitMain(inout RayIntersection rayIntersection : SV_RayPayload, AttributeData attributeData : SV_IntersectionAttributes)
{
	// The first thing that we should do is grab the intersection vertice
    IntersectionVertice currentvertex;
    CurrentIntersectionVertice(attributeData, currentvertex);

    // Build the Frag inputs from the intersection vertice
    FragInputs fragInput;
    BuildFragInputsFromIntersection(currentvertex, fragInput);

    // Compute the view vector
    float3 viewWS = -rayIntersection.incidentDirection;

    // Make sure to add the additional travel distance
    float travelDistance = length(fragInput.positionRWS + _WorldSpaceCameraPos - rayIntersection.origin);
    rayIntersection.cone.width += travelDistance * rayIntersection.cone.spreadAngle;
    
    // Build the surfacedata and builtindata
    SurfaceData surfaceData;
    BuiltinData builtinData;
    GetSurfaceDataFromIntersection(fragInput, viewWS, currentvertex, rayIntersection.cone, surfaceData, builtinData);

    PositionInputs posInput;
    posInput.positionWS = fragInput.positionRWS;

    // Compute the bsdf data
    BSDFData bsdfData =  ConvertSurfaceDataToBSDFData(uint2(0, 0), surfaceData);

    // Compute the prelight data
    PreLightData preLightData = GetPreLightData(viewWS, posInput, bsdfData);

    builtinData.bakeDiffuseLighting *= (preLightData.diffuseFGD * bsdfData.diffuseColor);

    // Run the lightloop
    float3 diffuseLighting;
    float3 specularLighting;
    LightLoop(viewWS, posInput, preLightData, bsdfData, builtinData, diffuseLighting, specularLighting);

    // Color display for the moment
    rayIntersection.color = diffuseLighting + specularLighting;
}