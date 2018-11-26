// ----------------------------------------------------------------------------

// These are the samplers available in the HDRenderPipeline.
// Avoid declaring extra samplers as they are 4x SGPR each on GCN.
SAMPLER(s_point_clamp_sampler);
SAMPLER(s_linear_clamp_sampler);
SAMPLER(s_linear_repeat_sampler);
SAMPLER(s_trilinear_clamp_sampler);
SAMPLER(s_trilinear_repeat_sampler);

TEXTURE2D(_AmbientOcclusionTexture);
TEXTURE2D(_SsrLightingTexture);

TEXTURE2D(_DebugColorGradientTexture);


#include "Packages/com.unity.render-pipelines.high-definition/Runtime/ShaderLibrary/ShaderVariablesMatrixDefsLegacyUnity.hlsl"

float4x4 ApplyCameraTranslationToMatrix(float4x4 modelMatrix)
{
    // To handle camera relative rendering we substract the camera position in the model matrix
#if (SHADEROPTIONS_CAMERA_RELATIVE_RENDERING != 0)
    modelMatrix._m03_m13_m23 -= _WorldSpaceCameraPos;
#endif
    return modelMatrix;
}

float4x4 ApplyCameraTranslationToInverseMatrix(float4x4 inverseModelMatrix)
{
#if (SHADEROPTIONS_CAMERA_RELATIVE_RENDERING != 0)
    // To handle camera relative rendering we need to apply translation before converting to object space
    float4x4 translationMatrix = { { 1.0, 0.0, 0.0, _WorldSpaceCameraPos.x },{ 0.0, 1.0, 0.0, _WorldSpaceCameraPos.y },{ 0.0, 0.0, 1.0, _WorldSpaceCameraPos.z },{ 0.0, 0.0, 0.0, 1.0 } };
    return mul(inverseModelMatrix, translationMatrix);
#else
    return inverseModelMatrix;
#endif
}

float4x4 OptimizeProjectionMatrix(float4x4 M)
{
    // Matrix format (x = non-constant value).
    // Orthographic Perspective  Combined(OR)
    // | x 0 0 x |  | x 0 x 0 |  | x 0 x x |
    // | 0 x 0 x |  | 0 x x 0 |  | 0 x x x |
    // | x x x x |  | x x x x |  | x x x x | <- oblique projection row
    // | 0 0 0 1 |  | 0 0 x 0 |  | 0 0 x x |
    // Notice that some values are always 0.
    // We can avoid loading and doing math with constants.
    M._21_41 = 0;
    M._12_42 = 0;
    return M;
}

// Define Model Matrix Macro
// Note: In order to be able to define our macro to forbid usage of unity_ObjectToWorld/unity_WorldToObject
// We need to declare inline function. Using uniform directly mean they are expand with the macro

float4x4 glstate_matrix_projection;
float4x4 unity_ObjectToWorld;
float4x4 unity_WorldToObject;
float4 unity_LODFade; // x is the fade value ranging within [0,1]. y is x quantized into 16 levels
float4 unity_WorldTransformParams; // w is usually 1.0, or -1.0 for odd-negative scale transforms
float4 unity_RenderingLayer;

float4 unity_LightmapST;
float4 unity_DynamicLightmapST;

float4x4 unity_MatrixV;
float4x4 unity_MatrixInvV;
float4x4 unity_MatrixVP;

float3 _WorldSpaceCameraPos;

float4 _ScreenSize;                 // { w, h, 1 / w, 1 / h }
float4 _ScreenToTargetScale;        // { w / RTHandle.maxWidth, h / RTHandle.maxHeight } : xy = currFrame, zw = prevFrame

float4x4 GetRawUnityObjectToWorld() { return unity_ObjectToWorld; }
float4x4 GetRawUnityWorldToObject() { return unity_WorldToObject; }

#define UNITY_MATRIX_M     ApplyCameraTranslationToMatrix(GetRawUnityObjectToWorld())
#define UNITY_MATRIX_I_M   ApplyCameraTranslationToInverseMatrix(GetRawUnityWorldToObject())

#define unity_ObjectToWorld Use_Macro_UNITY_MATRIX_M_instead_of_unity_ObjectToWorld
#define unity_WorldToObject Use_Macro_UNITY_MATRIX_I_M_instead_of_unity_WorldToObject

#include "Packages/com.unity.render-pipelines.high-definition/Runtime/Lighting/LightLoop/ShaderVariablesLightLoop.hlsl"
#include "Packages/com.unity.render-pipelines.high-definition\Runtime\Lighting\AtmosphericScattering\ShaderVariablesAtmosphericScattering.hlsl"
#define SHADER_VARIABLES_INCLUDE_CB
#include "Packages/com.unity.render-pipelines.high-definition/Runtime/Lighting/LightLoop/ShaderVariablesLightLoop.hlsl"
#include "Packages/com.unity.render-pipelines.high-definition/Runtime/Material/SubsurfaceScattering/ShaderVariablesSubsurfaceScattering.hlsl"
#include "Packages/com.unity.render-pipelines.high-definition/Runtime/Lighting/ScreenSpaceLighting/ShaderVariablesScreenSpaceLighting.hlsl"
#include "Packages/com.unity.render-pipelines.high-definition\Runtime\Lighting\AtmosphericScattering\ShaderVariablesAtmosphericScattering.hlsl"

#include "Packages/com.unity.render-pipelines.high-definition/Runtime/ShaderLibrary/ShaderVariablesFunctions.hlsl"

float  _GlobalExtinction;

uint                                        _LightPerCellCount;
StructuredBuffer<uint>                      _RaytracingLightCluster;
StructuredBuffer<LightData>                 _LightDatasRT;
float3                                      _MinClusterPos;
float3                                      _MaxClusterPos;
uint                                        _PunctualLightCountRT;
uint                                        _AreaLightCountRT;