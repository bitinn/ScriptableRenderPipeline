// Engine includes
#include "UnityRaytracingMeshUtils.cginc"

// Structure that defines the current state of the intersection
struct RayIntersection
{
	// Direction of the current ray
	float3 incidentDirection;
	// Value that holds the color of the ray
	float3 color;
	// Value that tracks the current bounce index of the ray
	uint boundIndex;
};

struct AttributeData
{
	// Barycentric value of the intersection
	float2 barycentrics;
};

// Macro that interpolate any attribute using barycentric coordinates
#define INTERPOLATE_RAYTRACING_ATTRIBUTE(A0, A1, A2, BARYCENTRIC_COORDINATES) (A0 * BARYCENTRIC_COORDINATES.x + A1 * BARYCENTRIC_COORDINATES.y + A2 * BARYCENTRIC_COORDINATES.z)

// Minimal structure to fill
struct IntersectionVertice
{
	float3 	positionWS;
	float3 	normalWS;
};

IntersectionVertice FetchIntersectionVertex(uint vertexIndex)
{
    IntersectionVertice IntersectionVertice;
    IntersectionVertice.positionWS  = UnityRaytracingFetchVertexAttribute3(vertexIndex, kVertexAttributePosition);
    IntersectionVertice.normalWS    = UnityRaytracingFetchVertexAttribute3(vertexIndex, kVertexAttributeNormal);
    return IntersectionVertice;
}

IntersectionVertice GetCurrentIntersectionVertice(AttributeData attributeData)
{
	IntersectionVertice v0 = FetchIntersectionVertex(0);
	IntersectionVertice v1 = FetchIntersectionVertex(1);
	IntersectionVertice v2 = FetchIntersectionVertex(2);

	// Compute the full barycentric cooridinates
	float3 completeBarycentricCoordinates = float3(1.0 - attributeData.barycentrics.x - attributeData.barycentrics.y, attributeData.barycentrics.x, attributeData.barycentrics.y);

	IntersectionVertice currentVertice;
	currentVertice.positionWS = INTERPOLATE_RAYTRACING_ATTRIBUTE(v0.positionWS, v1.positionWS, v2.positionWS, completeBarycentricCoordinates);
	currentVertice.normalWS = INTERPOLATE_RAYTRACING_ATTRIBUTE(v0.normalWS, v1.normalWS, v2.normalWS, completeBarycentricCoordinates);
	return currentVertice;
}