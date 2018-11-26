#include "Packages/com.unity.render-pipelines.core/ShaderLibrary\CommonMaterial.hlsl"

// Generic function that handles the reflection code
[shader("anyhit")]
void AnyHitMain(inout RayIntersection rayIntersection : SV_RayPayload, AttributeData attributeData : SV_IntersectionAttributes)
{
	// The first thing that we should do is grab the intersection vertice
    IntersectionVertice currentvertex;
    CurrentIntersectionVertice(attributeData, currentvertex);

    // Build the Frag inputs from the intersection vertice
    FragInputs fragInput;
    BuildFragInputsFromIntersection(currentvertex, fragInput);

    // Compute the view vector
    float3 viewWS = -rayIntersection.incidentDirection;

    // Build the surfacedata and builtindata
    SurfaceData surfaceData;
    BuiltinData builtinData;
    GetSurfaceDataFromIntersection(fragInput, viewWS, currentvertex, rayIntersection.cone, surfaceData, builtinData);

    // If this fella is not opaque, then we ignore this hit
    if(builtinData.opacity < _AlphaCutoff)
    {
        IgnoreHit();
    }
    else
    {
        // If this fella is opaque, then we need to stop 
        rayIntersection.color = float3(0.0, 0.0, 0.0);
        AcceptHitAndEndSearch();
    }
}