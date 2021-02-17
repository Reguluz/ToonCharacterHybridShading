#ifndef UE4_PBR_INCLUDED
#define UE4_PBR_INCLUDED

#define kDieletricSpec half4(0.04, 0.04, 0.04, 1.0 - 0.04)

#define MEDIUMP_FLT_MAX    65504.0

#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/EntityLighting.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/ImageBasedLighting.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

struct ReguluzInputData
{
    float3  positionWS;
    half3   normalWS;
    half3   viewDirectionWS;
    float4  shadowCoord;
    half    fogCoord;
    half3   vertexLighting;
    half3   Lightmap;
    half3   SH;
};

uniform half _IndirectLightingColorScale;
uniform half _SpecularScale;
uniform half _FresnelScale;

// half3 EnvBRDF( half3 SpecularColor, half Roughness, half NoV )
// {
// 	// Importance sampled preintegrated G * F
    
// 	//float2 AB = Texture2DSampleLevel( PreIntegratedGF, PreIntegratedGFSampler, float2( NoV, Roughness ), 0 ).rg;
//     float2 AB = SampleAlbedoAlpha(float2( NoV, Roughness ), TEXTURE2D_ARGS(PreIntegratedGF, sampler_PreIntegratedGF)).rg;
// 	// Anything less than 2% is physically impossible and is instead considered to be shadowing 
// 	float3 GF = SpecularColor * AB.x + saturate( 50.0 * SpecularColor.g ) * AB.y;
// 	return GF;
// }

// float Luminance(float3 LinearColor)
// {
//     return dot( LinearColor, float3( 0.3, 0.59, 0.11 ) );
// }

float3 RGBMDecode( float4 rgbm, float MaxValue )
{
	return rgbm.rgb * (rgbm.a * MaxValue);
}

// Half precision version for mobile's high quality reflection
half MobileComputeMixingWeight(half IndirectIrradiance, half AverageBrightness, half Roughness)
{
	// Mirror surfaces should have no mixing, so they match reflections from other sources (SSR, planar reflections)
	half MixingAlpha = smoothstep(0, 1, saturate(Roughness /* View.ReflectionEnvironmentRoughnessMixingScaleBiasAndLargestWeight.x + View.ReflectionEnvironmentRoughnessMixingScaleBiasAndLargestWeight.y*/));

	// We have high frequency directional data but low frequency spatial data in the envmap.
	// We have high frequency spatial data but low frequency directional data in the lightmap.
	// So, we combine the two for the best of both. This is done by removing the low spatial frequencies from the envmap and replacing them with the lightmap data.
	// This is only done with luma so as to not get odd color shifting.
	half MixingWeight = IndirectIrradiance / max(AverageBrightness, .0001f);

	MixingWeight = min(MixingWeight, 1/*View.ReflectionEnvironmentRoughnessMixingScaleBiasAndLargestWeight.z*/);

	return lerp(1.0f, MixingWeight, MixingAlpha);
}

// inline void InitializeBRDFData(half3 albedo, half metallic, half3 specular, half roughness, half alpha, out BRDFData outBRDFData)
// {
// #ifdef _SPECULAR_SETUP
//     half reflectivity = ReflectivitySpecular(specular);
//     half oneMinusReflectivity = 1.0 - reflectivity;

//     outBRDFData.diffuse = albedo * (half3(1.0h, 1.0h, 1.0h) - specular);
//     outBRDFData.specular = specular;
// #else

//     half oneMinusReflectivity = OneMinusReflectivityMetallic(metallic);
//     half reflectivity = 1.0 - oneMinusReflectivity;

//     outBRDFData.diffuse = albedo * oneMinusReflectivity;
//     outBRDFData.specular = lerp(kDieletricSpec.rgb, albedo, metallic);
// #endif

//     outBRDFData.grazingTerm = saturate(1 - roughness + reflectivity);
//     outBRDFData.perceptualRoughness = RoughnessToPerceptualRoughness(roughness);
//     outBRDFData.roughness = max(roughness, HALF_MIN);
//     outBRDFData.roughness2 = outBRDFData.roughness * outBRDFData.roughness;

//     outBRDFData.normalizationTerm = outBRDFData.roughness * 4.0h + 2.0h;
//     outBRDFData.roughness2MinusOne = outBRDFData.roughness2 - 1.0h;

// #ifdef _ALPHAPREMULTIPLY_ON
//     outBRDFData.diffuse *= alpha;
//     alpha = alpha * oneMinusReflectivity + reflectivity;
// #endif
// }

half3 EnvBRDFApprox( half3 SpecularColor, half Roughness, half NoV)
{
	// [ Lazarov 2013, "Getting More Physical in Call of Duty: Black Ops II" ]
	// Adaptation to fit our G term.
	const half4 c0 = { -1, -0.0275, -0.572, 0.022 };
	const half4 c1 = { 1, 0.0425, 1.04, -0.04 };
	half4 r = Roughness * c0 + c1;
	half a004 = min( r.x * r.x, exp2( -9.28 * NoV ) ) * r.x + r.y;
	half2 AB = half2( -1.04, 1.04 ) * a004 + r.zw;

	// Anything less than 2% is physically impossible and is instead considered to be shadowing
	// Note: this is needed for the 'specular' show flag to work, since it uses a SpecularColor of 0
	AB.y *= saturate( 50.0 * SpecularColor.g );
	return SpecularColor * AB.x + AB.y;
}

half GGX_Mobile(half Roughness, half NoH, half3 H, half3 N)
{
    // Walter et al. 2007, "Microfacet Models for Refraction through Rough Surfaces"

    // In mediump, there are two problems computing 1.0 - NoH^2
    // 1) 1.0 - NoH^2 suffers floating point cancellation when NoH^2 is close to 1 (highlights)
    // 2) NoH doesn't have enough precision around 1.0
    // Both problem can be fixed by computing 1-NoH^2 in highp and providing NoH in highp as well

    // However, we can do better using Lagrange's identity:
    //      ||a x b||^2 = ||a||^2 ||b||^2 - (a . b)^2
    // since N and H are unit vectors: ||N x H||^2 = 1.0 - NoH^2
    // This computes 1.0 - NoH^2 directly (which is close to zero in the highlights and has
    // enough precision).
    // Overall this yields better performance, keeping all computations in mediump

	float3 NxH = cross(N, H);
	float OneMinusNoHSqr = dot(NxH, NxH);

	half a = Roughness * Roughness;
	float n = NoH * a;
	float p = a / (OneMinusNoHSqr + n * n);
	float d = p * p;
	return min(d, MEDIUMP_FLT_MAX);
}
half PhongApprox( half Roughness, half RoL )
{
	half a = Roughness * Roughness;			// 1 mul
	//!! Ronin Hack?
	a = max(a, 0.008);						// avoid underflow in FP16, next sqr should be bigger than 6.1e-5
	half a2 = a * a;						// 1 mul
	half rcp_a2 = rcp(a2);					// 1 rcp
	//half rcp_a2 = exp2( -6.88886882 * Roughness + 6.88886882 );

	// Spherical Gaussian approximation: pow( x, n ) ~= exp( (n + 0.775) * (x - 1) )
	// Phong: n = 0.5 / a2 - 0.5
	// 0.5 / ln(2), 0.275 / ln(2)
	half c = 0.72134752 * rcp_a2 + 0.39674113;	// 1 mad
	half p = rcp_a2 * exp2(c * RoL - c);		// 2 mad, 1 exp2, 1 mul
	// Total 7 instr
	return min(p, rcp_a2);						// Avoid overflow/underflow on Mali GPUs
}
half CalcSpecular(half Roughness, float RoL, float NoH, float3 H, float3 N)
{
    // return PhongApprox(Roughness, RoL);
	return (Roughness*0.25 + 0.25) * GGX_Mobile(Roughness, NoH, H, N);
}

half4 FakeLightmapwithLuma(half3 lightmap)
{
    half LogL = Luminance( lightmap );					// 1 dot

	// LogL -> L
	const half LogBlackPoint = 0.00390625;	// exp2(-8);
	half L = exp2( LogL * 16 - 8 ) - LogBlackPoint;		// 1 exp2, 1 smad, 1 ssub
//************No Layer2 so remove branch*************    
// #if USE_LM_DIRECTIONALITY
// 	// Alpha doesn't matter, will scaled by zero
// 	float4 SH = Lightmap1 * GetLightmapData(LightmapDataIndex).LightMapScale[1] + GetLightmapData(LightmapDataIndex).LightMapAdd[1];	// 1 vmad

// 	// Sample SH with normal
// 	half Directionality = max( 0.0, dot( SH, float4(WorldNormal.yzx, 1) ) );	// 1 dot, 1 smax
// #else
	half Directionality = 0.6;
// #endif
//***************************************************
	half Luma = L * Directionality;
	half3 Color = lightmap * (Luma / LogL);				// 1 rcp, 1 smul, 1 vmul

	return half4( Color, Luma );
}

half3 GetImageBasedReflectionLighting(half Roughness, half IndirectIrradiance, half3 reflectVector, half3 normalWS)
{
// #if HQ_REFLECTIONS
// 	half3 SpecularIBL = BlendReflectionCaptures(MaterialParameters, Roughness, IndirectIrradiance);
// #else

	// Compute fractional mip from roughness
	half AbsoluteSpecularMip = PerceptualRoughnessToMipmapLevel(RoughnessToPerceptualRoughness(Roughness));//replaced UE4 ComputeReflectionCaptureMipFromRoughness(Roughness, CubemapMaxMip);
	// Fetch from cubemap and convert to linear HDR
    half3 SpecularIBL = DecodeHDREnvironment(SAMPLE_TEXTURECUBE_LOD(unity_SpecCube0, samplerunity_SpecCube0, reflectVector, AbsoluteSpecularMip), unity_SpecCube0_HDR);
	// half4 SpecularIBLSample = MobileReflectionCapture.Texture.SampleLevel(MobileReflectionCapture.TextureSampler, ProjectedCaptureVector, AbsoluteSpecularMip);
	// if (UsingSkyReflection)
	// {
		// SpecularIBL = SpecularIBLSample.rgb;
	// 	// Apply sky colour if the reflection map is the sky.
		// SpecularIBL *= SampleSH(normalWS);//ResolvedView.SkyLightColor.rgb;
	// }
	// else
	// {
		// SpecularIBL = RGBMDecode(SpecularIBLSample, 16.0);
		SpecularIBL = SpecularIBL * SpecularIBL;
		
		//To keep ImageBasedReflectionLighting conherence with PC, use ComputeMixingWeight instead of InvReflectionAverageBrightness to calulate the IBL constribution
		SpecularIBL *= MobileComputeMixingWeight(IndirectIrradiance, Luminance(_GlossyEnvironmentColor)/*MobileReflectionCapture.Params.x*/, Roughness);

	// }

// #endif

	SpecularIBL *= _IndirectLightingColorScale;

	return SpecularIBL;
}


half4 SpecularFragmentPBR(ReguluzInputData inputData, half3 albedo, half metallic, half3 specular,
    half roughness, half occlusion, half4 emission, half alpha)
{
    //**********Init Diffuse and Specular color
	half3 DiffuseColor = albedo - albedo * metallic;
    half3 DielectricSpecular = 0.08 * specular;
	half3 SpecularColor = (DielectricSpecular - DielectricSpecular * metallic) + albedo * metallic;

    //**********Init other properties
    half NoV = max( dot( inputData.normalWS, inputData.viewDirectionWS), 0 );

    //**********EnvironmentBRDF
    SpecularColor = EnvBRDFApprox( SpecularColor, roughness, NoV);
   
    //**********Init Color and IndirectIrradiance
    half3 Color = 0;
	//To keep IndirectLightingCache conherence with PC, initialize the IndirectIrradiance to zero.
	half IndirectIrradiance = 0;

    //**********Add LightMap & SH
#ifdef LIGHTMAP_ON
    half4 FakeUE4Lightmap = FakeLightmapwithLuma(inputData.Lightmap);
    Color += FakeUE4Lightmap.rgb * DiffuseColor * _IndirectLightingColorScale;
    IndirectIrradiance = FakeUE4Lightmap.a;
#else
    // No IndirectLightingCache so removed
    // half3 PointIndirectLighting = IndirectLightingCache.IndirectLightingSHSingleCoefficient;
    // half3 DiffuseGI = PointIndirectLighting;

    half3 DiffuseGI = saturate(inputData.SH);
    IndirectIrradiance = Luminance(DiffuseGI);
    Color += DiffuseColor * DiffuseGI * _IndirectLightingColorScale;
	// return half4(DiffuseGI,1);
#endif
    half Shadow = 0;//Shadow = GetPrimaryPrecomputedShadowMask(Interpolants).r; when define LQ_TEXTURE_LIGHTMAP, it returns 0;
    //**********Add AO
    half MaterialAO = occlusion;
    Color *= MaterialAO;	
    IndirectIrradiance *= MaterialAO;
   
    // fresnel (only in Unity)
    half grazingTerm = saturate( 1 - roughness + 1 - OneMinusReflectivityMetallic(metallic));
    float surfaceReduction = 1.0 / (roughness * roughness + 1.0);
    half fresnelTerm = Pow4(1.0 - saturate(NoV));
    Color += surfaceReduction * lerp(SpecularColor, grazingTerm.xxx * inputData.SH, fresnelTerm);
    
    //**********Calculate Shadow
    //****************Cascade Shadowmap
    Light mainLight = GetMainLight(inputData.shadowCoord);//Only in Unity,to get shadowmap first
    Shadow = mainLight.shadowAttenuation;
    float NoL = max(0, dot(inputData.normalWS, mainLight.direction));
    float3 R = reflect(-inputData.viewDirectionWS, inputData.normalWS);//2 * NoL * inputData.normalWS - mainLight.direction;
    float RoL = max(0, dot(R, mainLight.direction));
    float3 H = normalize(inputData.viewDirectionWS + mainLight.direction);
    float NoH = max(0,dot(inputData.normalWS, H));
    
// MobileDirectionalLight.DirectionalLightDistanceFadeMADAndSpecularScale.z saves SpecularScale for direction light.
    Color += (Shadow * NoL) * mainLight.color * (DiffuseColor + SpecularColor * _SpecularScale /*UE4 * MobileDirectionalLight.DirectionalLightDistanceFadeMADAndSpecularScale.z*/ * CalcSpecular(roughness, RoL, NoH, H, inputData.normalWS));
    // Environment map has been prenormalized, scale by lightmap luminance
    half3 SpecularIBL = GetImageBasedReflectionLighting(roughness, IndirectIrradiance, R, inputData.normalWS);
    // return half4( SpecularIBL,1);

    // return  half4(SpecularIBL,1);
    // #if MATERIAL_PLANAR_FORWARD_REFLECTIONS
    //     BRANCH
    //     if (abs(dot(PlanarReflectionStruct.ReflectionPlane.xyz, 1)) > .0001f)
    //     {
    //         half4 PlanarReflection = GetPlanarReflection(MaterialParameters.AbsoluteWorldPosition, MaterialParameters.WorldNormal, Roughness);
    //         // Planar reflections win over reflection environment
    //         SpecularIBL = lerp(SpecularIBL, PlanarReflection.rgb, PlanarReflection.a);
    //     }
    // #endif
    Color += SpecularIBL * SpecularColor;
// #if ENABLE_SKY_LIGHT
// 			//@mw todo
// 			// TODO: Also need to do specular.
// #if MATERIAL_TWO_SIDED && LQ_TEXTURE_LIGHTMAP
			// if (NoL == 0)
			// {
// #endif
			half3 SkyDiffuseLighting = SampleSH(inputData.normalWS);//GetSkySHDiffuseSimple(MaterialParameters.WorldNormal);
// 		#if MATERIAL_SHADINGMODEL_SINGLELAYERWATER
// 			WaterDiffuseIndirectLuminance += SkyDiffuseLighting;
// 		#endif
            Color += SkyDiffuseLighting * unity_AmbientSky * DiffuseColor * MaterialAO;
// #if MATERIAL_TWO_SIDED && LQ_TEXTURE_LIGHTMAP
			// }
// #endif
// 		#endif
#ifdef _ADDITIONAL_LIGHTS
    uint pixelLightCount = GetAdditionalLightsCount();
    for (uint lightIndex = 0u; lightIndex < pixelLightCount; ++lightIndex)
    {
        Light light = GetAdditionalLight(lightIndex, inputData.positionWS);
        float3 ToLight = light.direction;// - inputData.normalWS;
        float DistanceSqr = dot(ToLight, ToLight);
        float3 L = ToLight * rsqrt(DistanceSqr);
        float3 H = normalize(inputData.viewDirectionWS + L);

        float PointNoL = max(0, dot(inputData.normalWS, L));
        float PointRoL = max(0, dot(reflect(mainLight.direction, inputData.normalWS), L));
        float PointNoH = max(0, dot(inputData.normalWS, H));

        Color += (light.distanceAttenuation * PointNoL) * light.color * DiffuseColor;
        // Color += LightingPhysicallyBased(brdfData, light, inputData.normalWS, inputData.viewDirectionWS);
    }
#endif

// #ifdef _ADDITIONAL_LIGHTS_VERTEX
//     color += inputData.vertexLighting * brdfData.diffuse;
// #endif

    Color += emission.rgb * emission.a;
    return half4(Color, alpha);
}
#endif