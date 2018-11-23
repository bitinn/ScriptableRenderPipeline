//-----------------------------------------------------------------------------
// Helper functions for roughness
//-----------------------------------------------------------------------------

real PerceptualRoughnessToRoughness(real perceptualRoughness)
{
    return perceptualRoughness * perceptualRoughness;
}

real RoughnessToPerceptualRoughness(real roughness)
{
    return sqrt(roughness);
}

real RoughnessToPerceptualSmoothness(real roughness)
{
    return 1.0 - sqrt(roughness);
}

real PerceptualSmoothnessToRoughness(real perceptualSmoothness)
{
    return (1.0 - perceptualSmoothness) * (1.0 - perceptualSmoothness);
}

real PerceptualSmoothnessToPerceptualRoughness(real perceptualSmoothness)
{
    return (1.0 - perceptualSmoothness);
}

// WARNING: this has been deprecated, and should not be used!
// Using roughness values of 0 leads to INFs and NANs. The only sensible place to use the roughness
// value of 0 is IBL, so we do not modify the perceptual roughness which is used to select the MIP map level.
// Note: making the constant too small results in aliasing.
real ClampRoughnessForAnalyticalLights(real roughness)
{
    return max(roughness, 1.0 / 1024.0);
}

void ConvertValueAnisotropyToValueTB(real value, real anisotropy, out real valueT, out real valueB)
{
    // Use the parametrization of Sony Imageworks.
    // Ref: Revisiting Physically Based Shading at Imageworks, p. 15.
    valueT = value * (1 + anisotropy);
    valueB = value * (1 - anisotropy);
}

void ConvertAnisotropyToRoughness(real perceptualRoughness, real anisotropy, out real roughnessT, out real roughnessB)
{
    real roughness = PerceptualRoughnessToRoughness(perceptualRoughness);
    ConvertValueAnisotropyToValueTB(roughness, anisotropy, roughnessT, roughnessB);
}

void ConvertRoughnessTAndAnisotropyToRoughness(real roughnessT, real anisotropy, out real roughness)
{
    roughness = roughnessT / (1 + anisotropy);
}

void ConvertRoughnessToAnisotropy(real roughnessT, real roughnessB, out real anisotropy)
{
    anisotropy = ((roughnessT - roughnessB) / max(roughnessT + roughnessB, 0.0001));
}

// WARNING: this has been deprecated, and should not be used!
// Same as ConvertAnisotropyToRoughness but
// roughnessT and roughnessB are clamped, and are meant to be used with punctual and directional lights.
void ConvertAnisotropyToClampRoughness(real perceptualRoughness, real anisotropy, out real roughnessT, out real roughnessB)
{
    ConvertAnisotropyToRoughness(perceptualRoughness, anisotropy, roughnessT, roughnessB);

    roughnessT = ClampRoughnessForAnalyticalLights(roughnessT);
    roughnessB = ClampRoughnessForAnalyticalLights(roughnessB);
}

// Use with stack BRDF (clear coat / coat) - This only used same equation to convert from Blinn-Phong spec power to Beckmann roughness
real RoughnessToVariance(real roughness)
{
    return 2.0 / Sq(roughness) - 2.0;
}

real VarianceToRoughness(real variance)
{
    return sqrt(2.0 / (variance + 2.0));
}

// Normal Map Filtering - This must match HDRP\Editor\AssetProcessors\NormalMapFilteringTexturePostprocessor.cs - highestVarianceAllowed (TODO: Move in core)
#define NORMALMAP_HIGHEST_VARIANCE 0.03125

float DecodeVariance(float gradientW)
{
    return gradientW * NORMALMAP_HIGHEST_VARIANCE;
}

// Return modified perceptualSmoothness based on provided variance (get from GeometricNormalVariance + TextureNormalVariance)
float NormalFiltering(float perceptualSmoothness, float variance, float threshold)
{
    float roughness = PerceptualSmoothnessToRoughness(perceptualSmoothness);
    // Ref: Geometry into Shading - http://graphics.pixar.com/library/BumpRoughness/paper.pdf - equation (3)
    float squaredRoughness = saturate(roughness * roughness + min(2.0 * variance, threshold * threshold)); // threshold can be really low, square the value for easier control

    return RoughnessToPerceptualSmoothness(sqrt(squaredRoughness));
}