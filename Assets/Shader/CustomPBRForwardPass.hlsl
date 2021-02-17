#ifndef UNIVERSAL_FORWARD_LIT_PASS_INCLUDED
#define UNIVERSAL_FORWARD_LIT_PASS_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/SurfaceInput.hlsl"
#include "CustomPBRFunction.hlsl"

CBUFFER_START(UnityPerMaterial)
float4 _BaseMap_ST;
half4 _BaseColor;
half _Specular;
float4 _SpecularMap_ST;
half4 _EmissionColor;
half _Cutoff;
half _Roughness;
half _Metallic;
half _BumpScale;
half _OcclusionStrength;
CBUFFER_END

TEXTURE2D(_PBRParams);       SAMPLER(sampler_PBRParams);
TEXTURE2D(_OcclusionMap);       SAMPLER(sampler_OcclusionMap);
TEXTURE2D(_MetallicMap);   SAMPLER(sampler_MetallicMap);
TEXTURE2D(_RoughnessMap);       SAMPLER(sampler_RoughnessMap);
TEXTURE2D(_SpecularMap);       SAMPLER(sampler_SpecularMap);
TEXTURE2D(_CubeMap);        SAMPLER(sampler_CubeMap);
//Definated in SurfaceInput.hlsl
// TEXTURE2D(_BaseMap);            SAMPLER(sampler_BaseMap);
// TEXTURE2D(_BumpMap);            SAMPLER(sampler_BumpMap);
// TEXTURE2D(_EmissionMap);        SAMPLER(sampler_EmissionMap);

// Must match Universal ShaderGraph master node
struct UESurfaceData
{
    half3 albedo;
    half3 specular;
    half  metallic;
    half  roughness;
    half3 normalTS;
    half4 emission;
    half  occlusion;
    half  alpha;
};

struct Attributes
{
    float4 positionOS   : POSITION;
    float3 normalOS     : NORMAL;
    float4 tangentOS    : TANGENT;
    float2 texcoord     : TEXCOORD0;
    float2 lightmapUV   : TEXCOORD1;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct ReguluzVarying
{
    float2 uv                       : TEXCOORD0;
    float2 lightmapUV               : TEXCOORD1;
    half3  vertexSH                 : TEXCOORD2;

#ifdef _ADDITIONAL_LIGHTS
    float3 positionWS               : TEXCOORD3;
#endif

#ifdef _NORMALMAP
    float4 normalWS                 : TEXCOORD4;    // xyz: normal, w: viewDir.x
    float4 tangentWS                : TEXCOORD5;    // xyz: tangent, w: viewDir.y
    float4 bitangentWS              : TEXCOORD6;    // xyz: bitangent, w: viewDir.z
#else
    float3 normalWS                 : TEXCOORD4;
    float3 viewDirWS                : TEXCOORD5;
#endif

    half4 fogFactorAndVertexLight   : TEXCOORD7; // x: fogFactor, yzw: vertex light

#ifdef _MAIN_LIGHT_SHADOWS
    float4 shadowCoord              : TEXCOORD8;
#endif

    float4 positionCS               : SV_POSITION;
    UNITY_VERTEX_INPUT_INSTANCE_ID
    UNITY_VERTEX_OUTPUT_STEREO
};

half SampleOcclusion(float2 uv)
{
#ifdef _OCCLUSIONMAP
// TODO: Controls things like these by exposing SHADER_QUALITY levels (low, medium, high)
#if defined(SHADER_API_GLES)
    return SAMPLE_TEXTURE2D(_OcclusionMap, sampler_OcclusionMap, uv).g;
#else
    half occ = SAMPLE_TEXTURE2D(_OcclusionMap, sampler_OcclusionMap, uv).g;
    return LerpWhiteTo(occ, _OcclusionStrength);
#endif
#else
    return 1.0;
#endif
}

void InitializeInputData(ReguluzVarying input, half3 normalTS, out ReguluzInputData inputData)
{
    inputData = (ReguluzInputData)0;



#ifdef _ADDITIONAL_LIGHTS
    inputData.positionWS = input.positionWS;
#endif

#ifdef _NORMALMAP
    half3 viewDirWS = half3(input.normalWS.w, input.tangentWS.w, input.bitangentWS.w);
    inputData.normalWS = TransformTangentToWorld(normalTS,
        half3x3(input.tangentWS.xyz, input.bitangentWS.xyz, input.normalWS.xyz));
#else
    half3 viewDirWS = input.viewDirWS;
    inputData.normalWS = input.normalWS;
#endif

    inputData.normalWS = NormalizeNormalPerPixel(inputData.normalWS);
    viewDirWS = SafeNormalize(viewDirWS);

    inputData.viewDirectionWS = viewDirWS;
#if defined(_MAIN_LIGHT_SHADOWS) && !defined(_RECEIVE_SHADOWS_OFF)
    inputData.shadowCoord = input.shadowCoord;
#else
    inputData.shadowCoord = float4(0, 0, 0, 0);
#endif
    inputData.fogCoord = input.fogFactorAndVertexLight.x;
    inputData.vertexLighting = input.fogFactorAndVertexLight.yzw;

    inputData.Lightmap = SampleLightmap(input.lightmapUV,  inputData.normalWS);
    inputData.SH = SampleSHPixel(input.vertexSH, inputData.normalWS);
}

///////////////////////////////////////////////////////////////////////////////
//                  Vertex and Fragment functions                            //
///////////////////////////////////////////////////////////////////////////////

// Used in Standard (Physically Based) shader
ReguluzVarying LitPassVertex(Attributes input)
{
    ReguluzVarying output = (ReguluzVarying)0;

    UNITY_SETUP_INSTANCE_ID(input);
    UNITY_TRANSFER_INSTANCE_ID(input, output);
    UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

    VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);
    VertexNormalInputs normalInput = GetVertexNormalInputs(input.normalOS, input.tangentOS);
    half3 viewDirWS = GetCameraPositionWS() - vertexInput.positionWS;
    half3 vertexLight = VertexLighting(vertexInput.positionWS, normalInput.normalWS);
    half fogFactor = ComputeFogFactor(vertexInput.positionCS.z);

    output.uv = TRANSFORM_TEX(input.texcoord, _BaseMap);

#ifdef _NORMALMAP
    output.normalWS = half4(normalize(normalInput.normalWS), viewDirWS.x);
    output.tangentWS = half4(normalInput.tangentWS, viewDirWS.y);
    output.bitangentWS = half4(normalInput.bitangentWS, viewDirWS.z);
#else
    output.normalWS = NormalizeNormalPerVertex(normalInput.normalWS);
    output.viewDirWS = viewDirWS;
#endif

    output.lightmapUV.xy = input.lightmapUV.xy * unity_LightmapST.xy + unity_LightmapST.zw;
    output.vertexSH = SampleSHVertex(output.normalWS.xyz);

    output.fogFactorAndVertexLight = half4(fogFactor, vertexLight);

#ifdef _ADDITIONAL_LIGHTS
    output.positionWS = vertexInput.positionWS;
#endif

#if defined(_MAIN_LIGHT_SHADOWS) && !defined(_RECEIVE_SHADOWS_OFF)
    output.shadowCoord = GetShadowCoord(vertexInput);
#endif

    output.positionCS = vertexInput.positionCS;

    return output;
}


half4 PBRSpecularFragment(ReguluzVarying input) : SV_Target
{
    UNITY_SETUP_INSTANCE_ID(input);
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

    UESurfaceData surfaceData;

    //PBRParams : metallic smoothness ao emission
//InitializeStandardLitSurfaceData(input.uv, surfaceData);
    half4 albedoAlpha = SampleAlbedoAlpha(input.uv, TEXTURE2D_ARGS(_BaseMap, sampler_BaseMap));
    surfaceData.alpha = Alpha(albedoAlpha.a, _BaseColor, _Cutoff);

    surfaceData.albedo = albedoAlpha.rgb * _BaseColor.rgb;
    half4 pbrparams = SAMPLE_TEXTURE2D(_PBRParams, sampler_PBRParams, input.uv);//  MRO  
    surfaceData.metallic = _Metallic * pbrparams.r;//SAMPLE_TEXTURE2D(_MetallicMap, sampler_MetallicMap, input.uv);
    surfaceData.specular = _Specular * SampleAlbedoAlpha(input.uv, TEXTURE2D_ARGS(_SpecularMap, sampler_SpecularMap));
    surfaceData.roughness = _Roughness * pbrparams.g;//SAMPLE_TEXTURE2D(_RoughnessMap, sampler_RoughnessMap, input.uv);
    surfaceData.normalTS = UnpackNormal(SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, input.uv)) * _BumpScale;//SampleNormal(input.uv, TEXTURE2D_ARGS(_BumpMap, sampler_BumpMap), _BumpScale);
    surfaceData.occlusion = _OcclusionStrength * pbrparams.b;//SampleOcclusion(input.uv);
    surfaceData.emission = half4(_EmissionColor.rgb,1) * SAMPLE_TEXTURE2D(_EmissionMap, sampler_EmissionMap, input.uv);//SampleEmission(input.uv, _EmissionColor.rgb, TEXTURE2D_ARGS(_EmissionMap, sampler_EmissionMap));
    

//old
    // InputData inputData;
    // InitializeInputData(input, surfaceData.normalTS, inputData);
    // half4 color = UniversalFragmentPBR(inputData, surfaceData.albedo, surfaceData.metallic, surfaceData.specular, surfaceData.smoothness, surfaceData.occlusion, surfaceData.emission, surfaceData.alpha);

//New
    ReguluzInputData inputData;
    InitializeInputData(input, surfaceData.normalTS, inputData);
    half4 color = SpecularFragmentPBR(inputData, surfaceData.albedo, surfaceData.metallic, surfaceData.specular,
    surfaceData.roughness, surfaceData.occlusion, surfaceData.emission, surfaceData.alpha);
    return color;
}

#endif
