//-----------------------------------------------------------------------------
// Includes
//-----------------------------------------------------------------------------

// SurfaceData is define in Lit.cs which generate Lit.cs.hlsl
#include "Packages/com.unity.render-pipelines.high-definition/Runtime/Material/Lit/Lit.cs.hlsl"
// Those define allow to include desired SSS/Transmission functions
#define MATERIAL_INCLUDE_SUBSURFACESCATTERING
#define MATERIAL_INCLUDE_TRANSMISSION
#include "Packages/com.unity.render-pipelines.high-definition/Runtime/Material/SubsurfaceScattering/SubsurfaceScattering.hlsl"
#include "Packages/com.unity.render-pipelines.high-definition/Runtime/Material/NormalBuffer.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/VolumeRendering.hlsl"

//-----------------------------------------------------------------------------
// Configuration
//-----------------------------------------------------------------------------

// Choose between Lambert diffuse and Disney diffuse (enable only one of them)
// #define USE_DIFFUSE_LAMBERT_BRDF

#define LIT_USE_GGX_ENERGY_COMPENSATION

// Enable reference mode for IBL and area lights
// Both reference define below can be define only if LightLoop is present, else we get a compile error
#ifdef HAS_LIGHTLOOP
// #define LIT_DISPLAY_REFERENCE_AREA
// #define LIT_DISPLAY_REFERENCE_IBL
#endif

// In forward we can chose between reading the normal from the normalBufferTexture or computing it again
// This is tradeoff between performance and quality. As we store the normal conpressed, recomputing again is higher quality.
// Uncomment this to get speed (to measure), let it comment to get quality
// #define FORWARD_MATERIAL_READ_FROM_WRITTEN_NORMAL_BUFFER

//-----------------------------------------------------------------------------
// Texture and constant buffer declaration
//-----------------------------------------------------------------------------

// GBuffer texture declaration
TEXTURE2D(_GBufferTexture0);
TEXTURE2D(_GBufferTexture1);
TEXTURE2D(_GBufferTexture2);
TEXTURE2D(_GBufferTexture3); // Bake lighting and/or emissive
TEXTURE2D(_GBufferTexture4); // Light layer or shadow mask
TEXTURE2D(_GBufferTexture5); // shadow mask

TEXTURE2D(_LightLayersTexture);
#ifdef SHADOWS_SHADOWMASK
TEXTURE2D(_ShadowMaskTexture); // Alias for shadow mask, so we don't need to know which gbuffer is used for shadow mask
#endif

#include "Packages/com.unity.render-pipelines.high-definition/Runtime/Material/LTCAreaLight/LTCAreaLight.hlsl"
#include "Packages/com.unity.render-pipelines.high-definition/Runtime/Material/PreIntegratedFGD/PreIntegratedFGD.hlsl"

//-----------------------------------------------------------------------------
// Definition
//-----------------------------------------------------------------------------

#define GBufferType0 float4
#define GBufferType1 float4
#define GBufferType2 float4
#define GBufferType3 float4
#define GBufferType4 float4
#define GBufferType5 float4

#ifdef LIGHT_LAYERS
#define GBUFFERMATERIAL_LIGHT_LAYERS 1
#else
#define GBUFFERMATERIAL_LIGHT_LAYERS 0
#endif

#ifdef SHADOWS_SHADOWMASK
#define GBUFFERMATERIAL_SHADOWMASK 1
#else
#define GBUFFERMATERIAL_SHADOWMASK 0
#endif

// Caution: This must be in sync with Lit.cs GetMaterialGBufferCount()
#define GBUFFERMATERIAL_COUNT (4 + GBUFFERMATERIAL_LIGHT_LAYERS + GBUFFERMATERIAL_SHADOWMASK)

#if defined(LIGHT_LAYERS) && defined(SHADOWS_SHADOWMASK)
#define OUT_GBUFFER_LIGHT_LAYERS outGBuffer4
#define OUT_GBUFFER_SHADOWMASK outGBuffer5
#elif defined(LIGHT_LAYERS)
#define OUT_GBUFFER_LIGHT_LAYERS outGBuffer4
#elif defined(SHADOWS_SHADOWMASK)
#define OUT_GBUFFER_SHADOWMASK outGBuffer4
#endif

#define HAS_REFRACTION (defined(_REFRACTION_PLANE) || defined(_REFRACTION_SPHERE))

// Enum for materialFeatureId (only use for encode/decode GBuffer)
#define GBUFFER_LIT_STANDARD         0
// we have not enough space (3bit) to store mat feature to have SSS and Transmission as bitmask, such why we have all variant
#define GBUFFER_LIT_SSS              1
#define GBUFFER_LIT_TRANSMISSION     2
#define GBUFFER_LIT_TRANSMISSION_SSS 3
#define GBUFFER_LIT_ANISOTROPIC      4
#define GBUFFER_LIT_IRIDESCENCE      5 // TODO

#define CLEAR_COAT_IOR 1.5
#define CLEAR_COAT_IETA (1.0 / CLEAR_COAT_IOR) // IETA is the inverse eta which is the ratio of IOR of two interface
#define CLEAR_COAT_F0 0.04 // IORToFresnel0(CLEAR_COAT_IOR)
#define CLEAR_COAT_ROUGHNESS 0.03
#define CLEAR_COAT_PERCEPTUAL_SMOOTHNESS RoughnessToPerceptualSmoothness(CLEAR_COAT_ROUGHNESS)
#define CLEAR_COAT_PERCEPTUAL_ROUGHNESS RoughnessToPerceptualRoughness(CLEAR_COAT_ROUGHNESS)

// It is safe to include this file after the G-Buffer macros above.
#include "Packages/com.unity.render-pipelines.high-definition/Runtime/Material/MaterialGBufferMacros.hlsl"

//-----------------------------------------------------------------------------
// Light and material classification for the deferred rendering path
// Configure what kind of combination is supported
//-----------------------------------------------------------------------------

// Lighting architecture and material are suppose to be decoupled files.
// However as we use material classification it is hard to be fully separated
// the dependecy is define in this include where there is shared define for material and lighting in case of deferred material.
// If a user do a lighting architecture without material classification, this can be remove
#include "Packages/com.unity.render-pipelines.high-definition/Runtime/Lighting/LightLoop/LightLoop.cs.hlsl"

// Currently disable SSR until critical editor fix is available
#undef LIGHTFEATUREFLAGS_SSREFLECTION
#define LIGHTFEATUREFLAGS_SSREFLECTION 0

// Combination need to be define in increasing "comlexity" order as define by FeatureFlagsToTileVariant
static const uint kFeatureVariantFlags[NUM_FEATURE_VARIANTS] =
{
    // Precomputed illumination (no dynamic lights) for all material types
    /*  0 */ LIGHTFEATUREFLAGS_SKY | LIGHTFEATUREFLAGS_ENV | LIGHTFEATUREFLAGS_SSREFLECTION | MATERIAL_FEATURE_MASK_FLAGS,

    /*  1 */ LIGHTFEATUREFLAGS_SKY | LIGHTFEATUREFLAGS_DIRECTIONAL | LIGHTFEATUREFLAGS_PUNCTUAL | MATERIALFEATUREFLAGS_LIT_STANDARD,
    /*  2 */ LIGHTFEATUREFLAGS_SKY | LIGHTFEATUREFLAGS_DIRECTIONAL | LIGHTFEATUREFLAGS_AREA | MATERIALFEATUREFLAGS_LIT_STANDARD,
    /*  3 */ LIGHTFEATUREFLAGS_SKY | LIGHTFEATUREFLAGS_DIRECTIONAL | LIGHTFEATUREFLAGS_ENV | LIGHTFEATUREFLAGS_SSREFLECTION | MATERIALFEATUREFLAGS_LIT_STANDARD,
    /*  4 */ LIGHTFEATUREFLAGS_SKY | LIGHTFEATUREFLAGS_DIRECTIONAL | LIGHTFEATUREFLAGS_PUNCTUAL | LIGHTFEATUREFLAGS_ENV | LIGHTFEATUREFLAGS_SSREFLECTION | MATERIALFEATUREFLAGS_LIT_STANDARD,
    /*  5 */ LIGHT_FEATURE_MASK_FLAGS_OPAQUE | MATERIALFEATUREFLAGS_LIT_STANDARD,

    // Standard with SSS and Transmission
    /*  6 */ LIGHTFEATUREFLAGS_SKY | LIGHTFEATUREFLAGS_DIRECTIONAL | LIGHTFEATUREFLAGS_PUNCTUAL | MATERIALFEATUREFLAGS_LIT_SUBSURFACE_SCATTERING | MATERIALFEATUREFLAGS_LIT_TRANSMISSION | MATERIALFEATUREFLAGS_LIT_STANDARD,
    /*  7 */ LIGHTFEATUREFLAGS_SKY | LIGHTFEATUREFLAGS_DIRECTIONAL | LIGHTFEATUREFLAGS_AREA | MATERIALFEATUREFLAGS_LIT_SUBSURFACE_SCATTERING | MATERIALFEATUREFLAGS_LIT_TRANSMISSION | MATERIALFEATUREFLAGS_LIT_STANDARD,
    /*  8 */ LIGHTFEATUREFLAGS_SKY | LIGHTFEATUREFLAGS_DIRECTIONAL | LIGHTFEATUREFLAGS_ENV | LIGHTFEATUREFLAGS_SSREFLECTION | MATERIALFEATUREFLAGS_LIT_SUBSURFACE_SCATTERING | MATERIALFEATUREFLAGS_LIT_TRANSMISSION | MATERIALFEATUREFLAGS_LIT_STANDARD,
    /*  9 */ LIGHTFEATUREFLAGS_SKY | LIGHTFEATUREFLAGS_DIRECTIONAL | LIGHTFEATUREFLAGS_PUNCTUAL | LIGHTFEATUREFLAGS_ENV | LIGHTFEATUREFLAGS_SSREFLECTION | MATERIALFEATUREFLAGS_LIT_SUBSURFACE_SCATTERING | MATERIALFEATUREFLAGS_LIT_TRANSMISSION | MATERIALFEATUREFLAGS_LIT_STANDARD,
    /* 10 */ LIGHT_FEATURE_MASK_FLAGS_OPAQUE | MATERIALFEATUREFLAGS_LIT_SUBSURFACE_SCATTERING | MATERIALFEATUREFLAGS_LIT_TRANSMISSION | MATERIALFEATUREFLAGS_LIT_STANDARD,

    // Anisotropy
    /* 11 */ LIGHTFEATUREFLAGS_SKY | LIGHTFEATUREFLAGS_DIRECTIONAL | LIGHTFEATUREFLAGS_PUNCTUAL | MATERIALFEATUREFLAGS_LIT_ANISOTROPY | MATERIALFEATUREFLAGS_LIT_STANDARD,
    /* 12 */ LIGHTFEATUREFLAGS_SKY | LIGHTFEATUREFLAGS_DIRECTIONAL | LIGHTFEATUREFLAGS_AREA | MATERIALFEATUREFLAGS_LIT_ANISOTROPY | MATERIALFEATUREFLAGS_LIT_STANDARD,
    /* 13 */ LIGHTFEATUREFLAGS_SKY | LIGHTFEATUREFLAGS_DIRECTIONAL | LIGHTFEATUREFLAGS_ENV | LIGHTFEATUREFLAGS_SSREFLECTION | MATERIALFEATUREFLAGS_LIT_ANISOTROPY | MATERIALFEATUREFLAGS_LIT_STANDARD,
    /* 14 */ LIGHTFEATUREFLAGS_SKY | LIGHTFEATUREFLAGS_DIRECTIONAL | LIGHTFEATUREFLAGS_PUNCTUAL | LIGHTFEATUREFLAGS_ENV | LIGHTFEATUREFLAGS_SSREFLECTION | MATERIALFEATUREFLAGS_LIT_ANISOTROPY | MATERIALFEATUREFLAGS_LIT_STANDARD,
    /* 15 */ LIGHT_FEATURE_MASK_FLAGS_OPAQUE | MATERIALFEATUREFLAGS_LIT_ANISOTROPY | MATERIALFEATUREFLAGS_LIT_STANDARD,

    // Standard with clear coat
    /* 16 */ LIGHTFEATUREFLAGS_SKY | LIGHTFEATUREFLAGS_DIRECTIONAL | LIGHTFEATUREFLAGS_PUNCTUAL | MATERIALFEATUREFLAGS_LIT_CLEAR_COAT | MATERIALFEATUREFLAGS_LIT_STANDARD,
    /* 17 */ LIGHTFEATUREFLAGS_SKY | LIGHTFEATUREFLAGS_DIRECTIONAL | LIGHTFEATUREFLAGS_AREA | MATERIALFEATUREFLAGS_LIT_CLEAR_COAT | MATERIALFEATUREFLAGS_LIT_STANDARD,
    /* 18 */ LIGHTFEATUREFLAGS_SKY | LIGHTFEATUREFLAGS_DIRECTIONAL | LIGHTFEATUREFLAGS_ENV | LIGHTFEATUREFLAGS_SSREFLECTION | MATERIALFEATUREFLAGS_LIT_CLEAR_COAT | MATERIALFEATUREFLAGS_LIT_STANDARD,
    /* 19 */ LIGHTFEATUREFLAGS_SKY | LIGHTFEATUREFLAGS_DIRECTIONAL | LIGHTFEATUREFLAGS_PUNCTUAL | LIGHTFEATUREFLAGS_ENV | LIGHTFEATUREFLAGS_SSREFLECTION | MATERIALFEATUREFLAGS_LIT_CLEAR_COAT | MATERIALFEATUREFLAGS_LIT_STANDARD,
    /* 20 */ LIGHT_FEATURE_MASK_FLAGS_OPAQUE | MATERIALFEATUREFLAGS_LIT_CLEAR_COAT | MATERIALFEATUREFLAGS_LIT_STANDARD,

    // Standard with Iridescence
    /* 21 */ LIGHTFEATUREFLAGS_SKY | LIGHTFEATUREFLAGS_DIRECTIONAL | LIGHTFEATUREFLAGS_PUNCTUAL | MATERIALFEATUREFLAGS_LIT_IRIDESCENCE | MATERIALFEATUREFLAGS_LIT_STANDARD,
    /* 22 */ LIGHTFEATUREFLAGS_SKY | LIGHTFEATUREFLAGS_DIRECTIONAL | LIGHTFEATUREFLAGS_AREA | MATERIALFEATUREFLAGS_LIT_IRIDESCENCE | MATERIALFEATUREFLAGS_LIT_STANDARD,
    /* 23 */ LIGHTFEATUREFLAGS_SKY | LIGHTFEATUREFLAGS_DIRECTIONAL | LIGHTFEATUREFLAGS_ENV | LIGHTFEATUREFLAGS_SSREFLECTION | MATERIALFEATUREFLAGS_LIT_IRIDESCENCE | MATERIALFEATUREFLAGS_LIT_STANDARD,
    /* 24 */ LIGHTFEATUREFLAGS_SKY | LIGHTFEATUREFLAGS_DIRECTIONAL | LIGHTFEATUREFLAGS_PUNCTUAL | LIGHTFEATUREFLAGS_ENV | LIGHTFEATUREFLAGS_SSREFLECTION | MATERIALFEATUREFLAGS_LIT_IRIDESCENCE | MATERIALFEATUREFLAGS_LIT_STANDARD,
    /* 25 */ LIGHT_FEATURE_MASK_FLAGS_OPAQUE | MATERIALFEATUREFLAGS_LIT_IRIDESCENCE | MATERIALFEATUREFLAGS_LIT_STANDARD,

    /* 26 */ LIGHT_FEATURE_MASK_FLAGS_OPAQUE | MATERIAL_FEATURE_MASK_FLAGS, // Catch all case with MATERIAL_FEATURE_MASK_FLAGS is needed in case we disable material classification
};

uint FeatureFlagsToTileVariant(uint featureFlags)
{
    for (int i = 0; i < NUM_FEATURE_VARIANTS; i++)
    {
        if ((featureFlags & kFeatureVariantFlags[i]) == featureFlags)
            return i;
    }
    return NUM_FEATURE_VARIANTS - 1;
}

#ifdef USE_INDIRECT

uint TileVariantToFeatureFlags(uint variant, uint tileIndex)
{
    if (variant == NUM_FEATURE_VARIANTS - 1)
    {
        // We don't have any compile-time feature information.
        // Therefore, we load the feature classification data at runtime to avoid
        // entering every single branch based on feature flags.
        return g_TileFeatureFlags[tileIndex];
    }
    else
    {
        // Return the compile-time feature flags.
        return kFeatureVariantFlags[variant];
    }
}

#endif // USE_INDIRECT

//-----------------------------------------------------------------------------
// Helper functions/variable specific to this material
//-----------------------------------------------------------------------------

#include "Packages/com.unity.render-pipelines.high-definition/Runtime/Lighting/LightDefinition.cs.hlsl"
#include "Packages/com.unity.render-pipelines.high-definition/Runtime/Lighting/Reflection/VolumeProjection.hlsl"
#include "Packages/com.unity.render-pipelines.high-definition/Runtime/Lighting/ScreenSpaceLighting/ScreenSpaceTracing.hlsl"
#include "Packages/com.unity.render-pipelines.high-definition/Runtime/Lighting/ScreenSpaceLighting/ScreenSpaceLighting.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Refraction.hlsl"

#if HAS_REFRACTION
    // Note that this option is referred as "Box" in the UI, we are keeping _REFRACTION_PLANE as shader define to avoid complication with already created materials.  
    #if defined(_REFRACTION_PLANE)
    #define REFRACTION_MODEL(V, posInputs, bsdfData) RefractionModelBox(V, posInputs.positionWS, bsdfData.normalWS, bsdfData.ior, bsdfData.thickness)
    #elif defined(_REFRACTION_SPHERE)
    #define REFRACTION_MODEL(V, posInputs, bsdfData) RefractionModelSphere(V, posInputs.positionWS, bsdfData.normalWS, bsdfData.ior, bsdfData.thickness)
    #endif
#endif

// This function is use to help with debugging and must be implemented by any lit material
// Implementer must take into account what are the current override component and
// adjust SurfaceData properties accordingdly
void ApplyDebugToSurfaceData(float3x3 worldToTangent, inout SurfaceData surfaceData)
{
#ifdef DEBUG_DISPLAY
    // Override value if requested by user
    // this can be use also in case of debug lighting mode like diffuse only
    bool overrideAlbedo = _DebugLightingAlbedo.x != 0.0;
    bool overrideSmoothness = _DebugLightingSmoothness.x != 0.0;
    bool overrideNormal = _DebugLightingNormal.x != 0.0;

    if (overrideAlbedo)
    {
        float3 overrideAlbedoValue = _DebugLightingAlbedo.yzw;
        surfaceData.baseColor = overrideAlbedoValue;
    }

    if (overrideSmoothness)
    {
        float overrideSmoothnessValue = _DebugLightingSmoothness.y;
        surfaceData.perceptualSmoothness = overrideSmoothnessValue;
    }

    if (overrideNormal)
    {
        surfaceData.normalWS = worldToTangent[2];
    }
#endif
}

void UpdateSurfaceDataFromNormalData(uint2 positionSS, inout BSDFData bsdfData)
{
    NormalData normalData;

    DecodeFromNormalBuffer(positionSS, normalData);

    bsdfData.normalWS = normalData.normalWS;
    bsdfData.perceptualRoughness = normalData.perceptualRoughness;
}

float3 GetNormalForShadowBias(BSDFData bsdfData)
{
    return bsdfData.normalWS;
}



NormalData ConvertSurfaceDataToNormalData(SurfaceData surfaceData)
{
    NormalData normalData;

    // Note: We can't handle clear coat material here, we have only one slot to store smoothness
    // and the buffer is the GBuffer1.
    normalData.normalWS = surfaceData.normalWS;
    normalData.perceptualRoughness = PerceptualSmoothnessToPerceptualRoughness(surfaceData.perceptualSmoothness);

    return normalData;
}

// include the surface to bsdf data file
#include "Packages/com.unity.render-pipelines.high-definition/Runtime/Material/Lit/LitSurfaceToBSDF.hlsl"

//-----------------------------------------------------------------------------
// conversion function for deferred
//-----------------------------------------------------------------------------

// GBuffer layout.
// GBuffer2 and GBuffer0.a interpretation depends on material feature enabled

//GBuffer0      RGBA8 sRGB  Gbuffer0 encode baseColor and so is sRGB to save precision. Alpha is not affected.
//GBuffer1      RGBA8
//GBuffer2      RGBA8
//GBuffer3      RGBA8


//FeatureName   Standard
//GBuffer0      baseColor.r,    baseColor.g,    baseColor.b,    specularOcclusion
//GBuffer1      normal.xy (1212),   perceptualRoughness
//GBuffer2      f0.r,   f0.g,   f0.b,   featureID(3) / coatMask(5)
//GBuffer3      bakedDiffuseLighting.rgb

//FeatureName   Subsurface Scattering + Transmission
//GBuffer0      baseColor.r,    baseColor.g,    baseColor.b,   diffusionProfile(4) / subsurfaceMask(4)
//GBuffer1      normal.xy (1212),   perceptualRoughness
//GBuffer2      specularOcclusion,  thickness,  diffusionProfile(4) / subsurfaceMask(4), featureID(3) / coatMask(5)
//GBuffer3      bakedDiffuseLighting.rgb

//FeatureName   Anisotropic
//GBuffer0      baseColor.r,    baseColor.g,    baseColor.b,    specularOcclusion
//GBuffer1      normal.xy (1212),   perceptualRoughness
//GBuffer2      anisotropy, tangent.x,  tangent.y(3) / metallic(5), featureID(3) / coatMask(5)
//GBuffer3      bakedDiffuseLighting.rgb

//FeatureName   Irridescence
//GBuffer0      baseColor.r,    baseColor.g,    baseColor.b,    specularOcclusion
//GBuffer1      normal.xy (1212),   perceptualRoughness
//GBuffer2      IOR,    thickness,  unused(3bit) / metallic(5), featureID(3) / coatMask(5)
//GBuffer3      bakedDiffuseLighting.rgb

// Note:
// For standard we have chose to always encode fresnel0. Even when we use metal/baseColor parametrization. This avoid
// compiler optimization problem that was using VGPR to deal with the various combination of metal non metal.

// For SSS, we move diffusionProfile(4) / subsurfaceMask(4) in GBuffer0.a so the forward SSS code only need to write into one RT
// and the SSS postprocess only need to read one RT
// We duplicate diffusionProfile / subsurfaceMask in GBuffer2.b so the compiler don't need to read the GBuffer0 before PostEvaluateBSDF
// The lighting code have been adapted to only apply diffuseColor at the end.
// This save VGPR as we don' need to keep the GBuffer0 value in register.

// The layout is also design to only require one RT for the material classification. All the material feature flags are deduced from GBuffer2.

// Encode SurfaceData (BSDF parameters) into GBuffer
// Must be in sync with RT declared in HDRenderPipeline.cs ::Rebuild
void EncodeIntoGBuffer( SurfaceData surfaceData
                        , BuiltinData builtinData
                        , uint2 positionSS
                        , out GBufferType0 outGBuffer0
                        , out GBufferType1 outGBuffer1
                        , out GBufferType2 outGBuffer2
                        , out GBufferType3 outGBuffer3
#if GBUFFERMATERIAL_COUNT > 4
                        , out GBufferType4 outGBuffer4
#endif
#if GBUFFERMATERIAL_COUNT > 5
                        , out GBufferType5 outGBuffer5
#endif
                        )
{
    // RT0 - 8:8:8:8 sRGB
    // Warning: the contents are later overwritten for Standard and SSS!
    outGBuffer0 = float4(surfaceData.baseColor, surfaceData.specularOcclusion);

    // This encode normalWS and PerceptualSmoothness into GBuffer1
    EncodeIntoNormalBuffer(ConvertSurfaceDataToNormalData(surfaceData), positionSS, outGBuffer1);

    // RT2 - 8:8:8:8
    uint materialFeatureId;

    if (HasFlag(surfaceData.materialFeatures, MATERIALFEATUREFLAGS_LIT_SUBSURFACE_SCATTERING | MATERIALFEATUREFLAGS_LIT_TRANSMISSION))
    {
        // Reminder that during GBuffer pass we know statically material materialFeatures
        if ((surfaceData.materialFeatures & (MATERIALFEATUREFLAGS_LIT_SUBSURFACE_SCATTERING | MATERIALFEATUREFLAGS_LIT_TRANSMISSION)) == (MATERIALFEATUREFLAGS_LIT_SUBSURFACE_SCATTERING | MATERIALFEATUREFLAGS_LIT_TRANSMISSION))
            materialFeatureId = GBUFFER_LIT_TRANSMISSION_SSS;
        else if ((surfaceData.materialFeatures & MATERIALFEATUREFLAGS_LIT_SUBSURFACE_SCATTERING) == MATERIALFEATUREFLAGS_LIT_SUBSURFACE_SCATTERING)
            materialFeatureId = GBUFFER_LIT_SSS;
        else
            materialFeatureId = GBUFFER_LIT_TRANSMISSION;

        // We perform the same encoding for SSS and transmission even if not used as it is the same cost
        // Note that regarding EncodeIntoSSSBuffer, as the lit.shader IS the deferred shader (and the SSS fullscreen pass is based on deferred encoding),
        // it know the details of the encoding, so it is fine to assume here how SSSBuffer0 is encoded

        // For the SSS feature, the alpha channel is overwritten with (diffusionProfile | subsurfaceMask).
        // It is done so that the SSS pass only has to read a single G-Buffer 0.
        // We move specular occlusion to the red channel of the G-Buffer 2.
        EncodeIntoSSSBuffer(ConvertSurfaceDataToSSSData(surfaceData), positionSS, outGBuffer0);

        // We duplicate the alpha channel of the G-Buffer 0 (for diffusion profile).
        // It allows us to delay reading the G-Buffer 0 until the end of the deferred lighting shader.
        outGBuffer2.rgb = float3(surfaceData.specularOcclusion, surfaceData.thickness, outGBuffer0.a);
    }
    else if (HasFlag(surfaceData.materialFeatures, MATERIALFEATUREFLAGS_LIT_ANISOTROPY))
    {
        materialFeatureId = GBUFFER_LIT_ANISOTROPIC;

        // Reconstruct the default tangent frame.
        float3x3 frame = GetLocalFrame(surfaceData.normalWS);

        // Compute the rotation angle of the actual tangent frame with respect to the default one.
        float sinFrame = dot(surfaceData.tangentWS, frame[1]);
        float cosFrame = dot(surfaceData.tangentWS, frame[0]);
        uint  storeSin = abs(sinFrame) < abs(cosFrame) ? 4 : 0;
        uint  quadrant = ((sinFrame < 0) ? 1 : 0) | ((cosFrame < 0) ? 2 : 0);

        // sin [and cos] are approximately linear up to [after] 45 degrees.
        float sinOrCos = min(abs(sinFrame), abs(cosFrame)) * sqrt(2);

        outGBuffer2.rgb = float3(surfaceData.anisotropy * 0.5 + 0.5,
                                 sinOrCos,
                                 PackFloatInt8bit(surfaceData.metallic, storeSin | quadrant, 8));
    }
    else if (HasFlag(surfaceData.materialFeatures, MATERIALFEATUREFLAGS_LIT_IRIDESCENCE))
    {
        materialFeatureId = GBUFFER_LIT_IRIDESCENCE;

        outGBuffer2.rgb = float3(surfaceData.iridescenceMask, surfaceData.iridescenceThickness,
                                 PackFloatInt8bit(surfaceData.metallic, 0, 8));
    }
    else // Standard
    {
        // In the case of standard or specular color we always convert to specular color parametrization before encoding,
        // so decoding is more efficient (it allow better optimization for the compiler and save VGPR)
        // This mean that on the decode side, MATERIALFEATUREFLAGS_LIT_SPECULAR_COLOR doesn't exist anymore
        materialFeatureId = GBUFFER_LIT_STANDARD;

        float3 diffuseColor = surfaceData.baseColor;
        float3 fresnel0     = surfaceData.specularColor;

        if (!HasFlag(surfaceData.materialFeatures, MATERIALFEATUREFLAGS_LIT_SPECULAR_COLOR))
        {
            // Convert from the metallic parametrization.
            diffuseColor = ComputeDiffuseColor(surfaceData.baseColor, surfaceData.metallic);
            fresnel0     = ComputeFresnel0(surfaceData.baseColor, surfaceData.metallic, DEFAULT_SPECULAR_VALUE);
        }

        outGBuffer0.rgb = diffuseColor;               // sRGB RT
        // outGBuffer2 is not sRGB, so use a fast encode/decode sRGB to keep precision
        outGBuffer2.rgb = FastLinearToSRGB(fresnel0); // TODO: optimize
    }

    // Ensure that surfaceData.coatMask is 0 if the feature is not enabled
    float coatMask = HasFlag(surfaceData.materialFeatures, MATERIALFEATUREFLAGS_LIT_CLEAR_COAT) ? surfaceData.coatMask : 0.0;
    // Note: no need to store MATERIALFEATUREFLAGS_LIT_STANDARD, always present
    outGBuffer2.a  = PackFloatInt8bit(coatMask, materialFeatureId, 8);

    // RT3 - 11f:11f:10f
    // In deferred we encode emissive color with bakeDiffuseLighting. We don't have the room to store emissiveColor.
    // It mean that any futher process that affect bakeDiffuseLighting will also affect emissiveColor, like SSAO for example.
    // Also if we don't have the room to store AO, then we apply it at this time on bakeDiffuseLighting which will cause a double occlusion with SSAO
#ifdef LIGHT_LAYERS
    outGBuffer3 = float4(builtinData.bakeDiffuseLighting + builtinData.emissiveColor, 0.0);
    // If we have light layers, take the opportunity to save AO and avoid double occlusion with SSAO
    OUT_GBUFFER_LIGHT_LAYERS = float4(0.0, 0.0, surfaceData.ambientOcclusion, builtinData.renderingLayers / 255.0);
#else
    outGBuffer3 = float4(builtinData.bakeDiffuseLighting * surfaceData.ambientOcclusion + builtinData.emissiveColor, 0.0);
#endif

#ifdef SHADOWS_SHADOWMASK
    OUT_GBUFFER_SHADOWMASK = BUILTIN_DATA_SHADOW_MASK;
#endif
}

// Fills the BSDFData. Also returns the (per-pixel) material feature flags inferred
// from the contents of the G-buffer, which can be used by the feature classification system.
// Note that return type is not part of the MACRO DECODE_FROM_GBUFFER, so it is safe to use return value for our need
// 'tileFeatureFlags' are compile-time flags provided by the feature classification system.
// If you're not using the feature classification system, pass UINT_MAX.
// Also, see comment in TileVariantToFeatureFlags. When we are the worse case (i.e last variant), we read the featureflags
// from the structured buffer use to generate the indirect draw call. It allow to not go through all branch and the branch is scalar (not VGPR)
uint DecodeFromGBuffer(uint2 positionSS, uint tileFeatureFlags, out BSDFData bsdfData, out BuiltinData builtinData)
{
    // Note: we have ZERO_INITIALIZE the struct, so bsdfData.diffusionProfile == DIFFUSION_PROFILE_NEUTRAL_ID,
    // bsdfData.anisotropy == 0, bsdfData.subsurfaceMask == 0, etc...
    ZERO_INITIALIZE(BSDFData, bsdfData);
    // Note: Some properties of builtinData are not used, just init all at 0 to silent the compiler
    ZERO_INITIALIZE(BuiltinData, builtinData);

    // Isolate material features.
    tileFeatureFlags &= MATERIAL_FEATURE_MASK_FLAGS;

    GBufferType0 inGBuffer0 = LOAD_TEXTURE2D(_GBufferTexture0, positionSS);
    GBufferType1 inGBuffer1 = LOAD_TEXTURE2D(_GBufferTexture1, positionSS);
    GBufferType2 inGBuffer2 = LOAD_TEXTURE2D(_GBufferTexture2, positionSS);

    // BuiltinData
    builtinData.bakeDiffuseLighting = LOAD_TEXTURE2D(_GBufferTexture3, positionSS).rgb;  // This also contain emissive (and * AO if no lightlayers)

    // Avoid to introduce a new variant for light layer as it is already long to compile
    if (_EnableLightLayers)
    {
        float4 inGBuffer4 = LOAD_TEXTURE2D(_LightLayersTexture, positionSS);
        // If we have light layers, take the opportunity to save AO and avoid double occlusion with SSAO
        bsdfData.ambientOcclusion = inGBuffer4.z;
        builtinData.renderingLayers = uint(inGBuffer4.w * 255.5);
    }
    else
    {
        bsdfData.ambientOcclusion = 1.0; // No value available, just settings 1.0. This mean double occlusion with SSAO.
        builtinData.renderingLayers = DEFAULT_LIGHT_LAYERS;
    }

    // We know the GBufferType no need to use abstraction
#ifdef SHADOWS_SHADOWMASK
    float4 shadowMaskGbuffer = LOAD_TEXTURE2D(_ShadowMaskTexture, positionSS);
    builtinData.shadowMask0 = shadowMaskGbuffer.x;
    builtinData.shadowMask1 = shadowMaskGbuffer.y;
    builtinData.shadowMask2 = shadowMaskGbuffer.z;
    builtinData.shadowMask3 = shadowMaskGbuffer.w;
#else
    builtinData.shadowMask0 = 1.0;
    builtinData.shadowMask1 = 1.0;
    builtinData.shadowMask2 = 1.0;
    builtinData.shadowMask3 = 1.0;
#endif

    // SurfaceData

    // Material classification only uses the G-Buffer 2.
    float coatMask;
    uint materialFeatureId;
    UnpackFloatInt8bit(inGBuffer2.a, 8, coatMask, materialFeatureId);

    uint pixelFeatureFlags    = MATERIALFEATUREFLAGS_LIT_STANDARD; // Only sky/background do not have the Standard flag.
    bool pixelHasSubsurface   = materialFeatureId == GBUFFER_LIT_TRANSMISSION_SSS || materialFeatureId == GBUFFER_LIT_SSS;
    bool pixelHasTransmission = materialFeatureId == GBUFFER_LIT_TRANSMISSION_SSS || materialFeatureId == GBUFFER_LIT_TRANSMISSION;
    bool pixelHasAnisotropy   = materialFeatureId == GBUFFER_LIT_ANISOTROPIC;
    bool pixelHasIridescence  = materialFeatureId == GBUFFER_LIT_IRIDESCENCE;
    bool pixelHasClearCoat    = coatMask > 0.0;

    // Disable pixel features disabled by the tile.
    pixelFeatureFlags |= tileFeatureFlags & (pixelHasSubsurface   ? MATERIALFEATUREFLAGS_LIT_SUBSURFACE_SCATTERING : 0);
    pixelFeatureFlags |= tileFeatureFlags & (pixelHasTransmission ? MATERIALFEATUREFLAGS_LIT_TRANSMISSION          : 0);
    pixelFeatureFlags |= tileFeatureFlags & (pixelHasAnisotropy   ? MATERIALFEATUREFLAGS_LIT_ANISOTROPY            : 0);
    pixelFeatureFlags |= tileFeatureFlags & (pixelHasIridescence  ? MATERIALFEATUREFLAGS_LIT_IRIDESCENCE           : 0);
    pixelFeatureFlags |= tileFeatureFlags & (pixelHasClearCoat    ? MATERIALFEATUREFLAGS_LIT_CLEAR_COAT            : 0);

    // In the case of material classification we assign tileFeatureFlags to bsdfData.materialFeatures
    // This mean that the branch inside the tile will be the same (coherency). Remember that a divergent branch
    // on AMD GCN mean we will execute both branch for all fragement. We setup at pixel level values
    // such that a particular branch will not have effect if it shouldn't. For example if SSS is enabled,
    // setup a sssMask of 0 don't have any effect and we can safely take the SSS branch for the tile.
    // Note that in the catch all variant of material classification we get the value from the structure buffer done
    // in the classification pass. Mean even in catch all, we it is high likely that we don't have tileFeatureFlags == MATERIAL_FEATURE_MASK_FLAGS case.

    // tileFeatureFlags == MATERIAL_FEATURE_MASK_FLAGS can appear in following situation
    // call from deferred.shader or other shader that doesn't peform material classification
    // call from last catch all variant in material classification, which mean we have all possible material inside a same tile (very rare)
    // call from a specific case in material classification (currently we have variant 0)
    // When this happen, we prefer to use the pixelFeatureFlags rather than the tileFeatureFlags as bsdfData.materialFeatures
    // because there is more likelihood to save performance (excep in the very rare case of catch all of material classification).
    // We can indeed have divergence inside a tile (like having aniso and not aniso)
    // but it is more likely that the whole time is convergent (like everything have SSS and clear coat).
    if (tileFeatureFlags == MATERIAL_FEATURE_MASK_FLAGS)
    {
        bsdfData.materialFeatures = pixelFeatureFlags;
        tileFeatureFlags = pixelFeatureFlags; // Required for the aniso test (see below)
    }
    else
    {
        bsdfData.materialFeatures = tileFeatureFlags;
    }

    // Decompress feature-agnostic data from the G-Buffer.
    float3 baseColor = inGBuffer0.rgb;

    NormalData normalData;
    DecodeFromNormalBuffer(inGBuffer1, positionSS, normalData);
    bsdfData.normalWS = normalData.normalWS;
    bsdfData.perceptualRoughness = normalData.perceptualRoughness;

    // Decompress feature-specific data from the G-Buffer.
    bool pixelHasMetallic = HasFlag(pixelFeatureFlags, MATERIALFEATUREFLAGS_LIT_ANISOTROPY | MATERIALFEATUREFLAGS_LIT_IRIDESCENCE);

    if (pixelHasMetallic)
    {
        float metallic;
        uint unused;
        UnpackFloatInt8bit(inGBuffer2.b, 8, metallic, unused);

        bsdfData.diffuseColor = ComputeDiffuseColor(baseColor, metallic);
        bsdfData.fresnel0     = ComputeFresnel0(baseColor, metallic, DEFAULT_SPECULAR_VALUE);
    }
    else
    {
        bsdfData.diffuseColor = baseColor;
        bsdfData.fresnel0     = FastSRGBToLinear(inGBuffer2.rgb); // Later possibly overwritten by SSS
    }

    if (HasFlag(pixelFeatureFlags, MATERIALFEATUREFLAGS_LIT_SUBSURFACE_SCATTERING | MATERIALFEATUREFLAGS_LIT_TRANSMISSION))
    {
        SSSData sssData;

        // We don't need to do this call, see comment below
        // DecodeFromSSSBuffer(inGBuffer0, positionSS, sssData);

        // Overwrite the diffusion profile/subsurfaceMask extracted by DecodeFromSSSBuffer().
        // We must do this so the compiler can optimize away the read from the G-Buffer 0 to the very end (in PostEvaluateBSDF)
        // Note that we don't use sssData.subsurfaceMask here. But it is still assign so we can have the information in the
        // material debug view + If we require it in the future.
        UnpackFloatInt8bit(inGBuffer2.b, 16, sssData.subsurfaceMask, sssData.diffusionProfile);

        // Reminder: when using SSS we exchange specular occlusion and subsurfaceMask/profileID
        bsdfData.specularOcclusion = inGBuffer2.r;

        // Note: both function assign profile and overwrite fresnel0 (both SSS and Transmission)
        // in case one feature is enabled and not the other.

        // The neutral value of subsurfaceMask is 0 (handled by ZERO_INITIALIZE).
        if (HasFlag(pixelFeatureFlags, MATERIALFEATUREFLAGS_LIT_SUBSURFACE_SCATTERING))
        {
            FillMaterialSSS(sssData.diffusionProfile, sssData.subsurfaceMask, bsdfData);
        }

        // The neutral value of thickness and transmittance is 0 (handled by ZERO_INITIALIZE).
        if (HasFlag(pixelFeatureFlags, MATERIALFEATUREFLAGS_LIT_TRANSMISSION))
        {
            FillMaterialTransmission(sssData.diffusionProfile, inGBuffer2.g, bsdfData);
        }
    }
    else
    {
        bsdfData.specularOcclusion = inGBuffer0.a;
    }

    // Special handling for anisotropy: When anisotropy is present in a tile, the whole tile will use anisotropy to avoid divergent evaluation of GGX that increase the cost
    // Note that it mean that when we have the worse case, we always use Anisotropy and shader like deferred.shader are always the worst case (but only used for debugging)
    if (HasFlag(tileFeatureFlags, MATERIALFEATUREFLAGS_LIT_ANISOTROPY))
    {
        float anisotropy = 0;
        float3x3 frame = GetLocalFrame(bsdfData.normalWS);

        if (HasFlag(pixelFeatureFlags, MATERIALFEATUREFLAGS_LIT_ANISOTROPY))
        {
            anisotropy = inGBuffer2.r * 2.0 - 1.0;

            float unused;
            uint tangentFlags;
            UnpackFloatInt8bit(inGBuffer2.b, 8, unused, tangentFlags);

            // Get the rotation angle of the actual tangent frame with respect to the default one.
            uint  quadrant = tangentFlags;
            uint  storeSin = tangentFlags & 4;
            float sinOrCos = inGBuffer2.g * rsqrt(2);
            float cosOrSin = sqrt(1 - sinOrCos * sinOrCos);
            float sinFrame = storeSin ? sinOrCos : cosOrSin;
            float cosFrame = storeSin ? cosOrSin : sinOrCos;
                  sinFrame = (quadrant & 1) ? -sinFrame : sinFrame;
                  cosFrame = (quadrant & 2) ? -cosFrame : cosFrame;

            // Rotate the reconstructed tangent around the normal.
            frame[0] = sinFrame * frame[1] + cosFrame * frame[0];
            frame[1] = cross(frame[2], frame[0]);
        }

        FillMaterialAnisotropy(anisotropy, frame[0], frame[1], bsdfData);
    }

    // The neutral value of iridescenceMask is 0 (handled by ZERO_INITIALIZE).
    if (HasFlag(pixelFeatureFlags, MATERIALFEATUREFLAGS_LIT_IRIDESCENCE))
    {
        FillMaterialIridescence(inGBuffer2.r, inGBuffer2.g, bsdfData);
    }

    // The neutral value of coatMask is 0 (handled by ZERO_INITIALIZE).
    if (HasFlag(pixelFeatureFlags, MATERIALFEATUREFLAGS_LIT_CLEAR_COAT))
    {
        // Modify perceptualRoughness
        FillMaterialClearCoatData(coatMask, bsdfData);
    }

    // Note: the full code below (for both roughness) only execute when we have enableAnisotropy == true, otherwise as we only use roughnessT compiler will optimize out
    // Mean that in the worst case we always execute it.

    // roughnessT and roughnessB are clamped, and are meant to be used with punctual and directional lights.
    // perceptualRoughness is not clamped, and is meant to be used for IBL.
    // perceptualRoughness can be modify by FillMaterialClearCoatData, so ConvertAnisotropyToClampRoughness must be call after
    ConvertAnisotropyToRoughness(bsdfData.perceptualRoughness, bsdfData.anisotropy, bsdfData.roughnessT, bsdfData.roughnessB);

    ApplyDebugToBSDFData(bsdfData);

    return pixelFeatureFlags;
}

// Function call from the material classification compute shader
uint MaterialFeatureFlagsFromGBuffer(uint2 positionSS)
{
    BSDFData bsdfData;
    BuiltinData unused;
    // Call the regular function, compiler will optimized out everything not used.
    // Note that all material feature flag bellow are in the same GBuffer (inGBuffer2) and thus material classification only sample one Gbuffer
    return DecodeFromGBuffer(positionSS, UINT_MAX, bsdfData, unused);
}

//-----------------------------------------------------------------------------
// Debug method (use to display values)
//-----------------------------------------------------------------------------

void GetSurfaceDataDebug(uint paramId, SurfaceData surfaceData, inout float3 result, inout bool needLinearToSRGB)
{
    GetGeneratedSurfaceDataDebug(paramId, surfaceData, result, needLinearToSRGB);

    // Overide debug value output to be more readable
    switch (paramId)
    {
    case DEBUGVIEW_LIT_SURFACEDATA_NORMAL_VIEW_SPACE:
        // Convert to view space
        result = TransformWorldToViewDir(surfaceData.normalWS) * 0.5 + 0.5;
        break;
    case DEBUGVIEW_LIT_SURFACEDATA_MATERIAL_FEATURES:
        result = (surfaceData.materialFeatures.xxx) / 255.0; // Aloow to read with color picker debug mode
        break;
    case DEBUGVIEW_LIT_SURFACEDATA_INDEX_OF_REFRACTION:
        result = saturate((surfaceData.ior - 1.0) / 1.5).xxx;
        break;
    }
}

void GetBSDFDataDebug(uint paramId, BSDFData bsdfData, inout float3 result, inout bool needLinearToSRGB)
{
    GetGeneratedBSDFDataDebug(paramId, bsdfData, result, needLinearToSRGB);

    // Overide debug value output to be more readable
    switch (paramId)
    {
    case DEBUGVIEW_LIT_BSDFDATA_NORMAL_VIEW_SPACE:
        // Convert to view space
        result = TransformWorldToViewDir(bsdfData.normalWS) * 0.5 + 0.5;
        break;
    case DEBUGVIEW_LIT_BSDFDATA_MATERIAL_FEATURES:
        result = (bsdfData.materialFeatures.xxx) / 255.0; // Aloow to read with color picker debug mode
        break;
    case DEBUGVIEW_LIT_BSDFDATA_IOR:
        result = saturate((bsdfData.ior - 1.0) / 1.5).xxx;
        break;
    }
}

#include "Packages/com.unity.render-pipelines.high-definition/Runtime/Material/Lit/LitPreLightData.hlsl"

//-----------------------------------------------------------------------------
// bake lighting function
//-----------------------------------------------------------------------------

// This define allow to say that we implement a ModifyBakedDiffuseLighting function to be call in PostInitBuiltinData
#define MODIFY_BAKED_DIFFUSE_LIGHTING

// This function allow to modify the content of (back) baked diffuse lighting when we gather builtinData
// This is use to apply lighting model specific code, like pre-integration, transmission etc...
// It is up to the lighting model implementer to chose if the modification are apply here or in PostEvaluateBSDF
void ModifyBakedDiffuseLighting(float3 V, PositionInputs posInput, SurfaceData surfaceData, inout BuiltinData builtinData)
{
    // In case of deferred, all lighting model operation are done before storage in GBuffer, as we store emissive with bakeDiffuseLighting

    // To get the data we need to do the whole process - compiler should optimize everything
    BSDFData bsdfData = ConvertSurfaceDataToBSDFData(posInput.positionSS, surfaceData);
    PreLightData preLightData = GetPreLightData(V, posInput, bsdfData);

    // Add GI transmission contribution to bakeDiffuseLighting, we then drop backBakeDiffuseLighting (i.e it is not used anymore, this save VGPR in forward and in deferred we can't store it anyway)
    if (HasFlag(bsdfData.materialFeatures, MATERIALFEATUREFLAGS_LIT_TRANSMISSION))
    {       
        builtinData.bakeDiffuseLighting += builtinData.backBakeDiffuseLighting * bsdfData.transmittance;
    }

    // For SSS we need to take into account the state of diffuseColor 
    if (HasFlag(bsdfData.materialFeatures, MATERIALFEATUREFLAGS_LIT_SUBSURFACE_SCATTERING))
    {
        bsdfData.diffuseColor = GetModifiedDiffuseColorForSSS(bsdfData);
    }

    // Premultiply (back) bake diffuse lighting information with DisneyDiffuse pre-integration
    builtinData.bakeDiffuseLighting *= preLightData.diffuseFGD * bsdfData.diffuseColor;
}

//-----------------------------------------------------------------------------
// light transport functions
//-----------------------------------------------------------------------------

LightTransportData GetLightTransportData(SurfaceData surfaceData, BuiltinData builtinData, BSDFData bsdfData)
{
    LightTransportData lightTransportData;

    // diffuseColor for lightmapping should basically be diffuse color.
    // But rough metals (black diffuse) still scatter quite a lot of light around, so
    // we want to take some of that into account too.

    float roughness = PerceptualRoughnessToRoughness(bsdfData.perceptualRoughness);
    lightTransportData.diffuseColor = bsdfData.diffuseColor + bsdfData.fresnel0 * roughness * 0.5 * surfaceData.metallic;
    lightTransportData.emissiveColor = builtinData.emissiveColor;

    return lightTransportData;
}

// include all the LitBSDF functions
#include "Packages/com.unity.render-pipelines.high-definition/Runtime/Material/Lit/LitBSDF.hlsl"