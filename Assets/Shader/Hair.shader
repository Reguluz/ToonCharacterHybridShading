Shader"14/CelHair"
{
    Properties
    {
        _Color("Color", Color) = (1,1,1,1)
        _MainTex ("Texture", 2D) = "white" {}
        _NormalTex ("Normal", 2D) = "bump" {}
        _SPColorTex("SPColorTex", 2D) = "black" {}
        _HighlightShiftTex("HighlightTex", 2D) = "black" {}
//        _CubeMap("CubeMap", Cube) = ""{}
        _Metallic("Metallic", Range(0,1)) = 0.5
        [HDR]_SpecColor1("SpecColor1", Color) = (1,1,1,1)
        [HDR]_SpecColor2("SpecColor1", Color) = (1,1,1,1)
        _Shift("Shift", Float) = 0.5
        _Layer1Offset("Layer1Offset", Float) = 0.5
        _Layer2Offset("Layer2Offset", Float) = 0.5
        _Layer1Intensity("Layer1Intensity", Float) = 1
        _Layer2Intensity("Layer2Intensity", Float) = 1
        _SpecMaskOffset("SpecMaskOffset", Range(0,1)) = 0.5
        _CubeIntensity("CubeIntensity", Float) = 1
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/SurfaceInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/BSDF.hlsl"
            #include "UE4PBRSpecularFunction.hlsl"
            
            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
                float3 normal : NORMAL;
                float4 tangent : TANGENT;
                float2 lightmapUV   : TEXCOORD1;
            };

            struct v2f
            {
                float4 positionOS : TEXCOORD1;
                float2 uv : TEXCOORD0;
                float4 positionCS : SV_POSITION;
                float3 normalWS : TEXCOORD2;
                float3 tangentWS : TEXCOORD3;
                float3 bitangentWS : TEXCOORD4;
                float4 shadowCoord : TEXCOORD5;
                float3 vertexSH : TEXCOORD6;
            };

            Texture2D _MainTex;
            SamplerState sampler_MainTex;
            Texture2D _NormalTex;
            SamplerState sampler_NormalTex;
            Texture2D _SPColorTex;
            SamplerState sampler_SPColorTex;
            Texture2D _HighlightShiftTex;
            SamplerState sampler_HighlightShiftTex;
            // TextureCube _CubeMap;
            // SamplerState sampler_CubeMap;

            float4 _SpecColor1;
            float4 _SpecColor2;
            float _Shift;
            float _SpecBalance;
            float _Metallic;
            float _SpecMaskOffset;
            float _Layer1Offset;
            float _Layer2Offset;
            float _Layer1Intensity;
            float _Layer2Intensity;
            float4 _Color;
            float _CubeIntensity;

            float3 ColorCurveMapping(float3 color, float k)
            {
	            return exp(log(max(color, int3(0, 0, 0))) * k);
            }
            float StrandSpecular(float3 T, float3 V, float L, float exponent)
            {
                float3 H = normalize(L + V);
                float dotTH = dot(T, H);
                float sinTH = sqrt(1.0 - dotTH * dotTH);
                sinTH =  ColorCurveMapping(sinTH, exponent);
                float dirAtten = smoothstep(-1, 0, saturate(dotTH+1));
                return saturate(dirAtten * sinTH);
            }


            float3 HairLighting (float3 tangent, float3 normal, float3 lightVec, 
                     float3 viewVec, float2 uv, float smoothness, float shiftTex)
            {
                float3 bitangent = -normalize(cross(tangent, normal));
                // shift tangents
                
                shiftTex *= _SpecMaskOffset;
                float3 t1 = ShiftTangent(bitangent, normal, /*primaryShift*/_Shift + shiftTex);
                float3 t2 = ShiftTangent(bitangent, normal, /*secondaryShift*/_Shift + shiftTex) ;
            
                // diffuse lighting
                smoothness = saturate(smoothness - 0.3);
                // specular lighting
                // add second specular term
                float3 specular = _SpecColor1 * StrandSpecular(t1, viewVec, lightVec, _Layer1Offset) * _Layer1Intensity;
                specular += _SpecColor2 * StrandSpecular(t2, viewVec, lightVec, _Layer2Offset) * _Layer2Intensity;
                return specular;
                
                // Final color
                // float3 o;
                // o.rgb = (diffuse + specular) * SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv); /** lightColor*/;
                // o.rgb *= ambOcc; 
                // o.a = tex2D(tAlpha, uv);

                return specular;
            }

            half3 MobileComputeMixingWeight(half3 IndirectIrradiance, half AverageBrightness, half Roughness)
	        {
		        half MixingAlpha = smoothstep(0, 1, saturate(Roughness /* View.ReflectionEnvironmentRoughnessMixingScaleBiasAndLargestWeight.x + View.ReflectionEnvironmentRoughnessMixingScaleBiasAndLargestWeight.y*/));
		        half3 MixingWeight = IndirectIrradiance / max(AverageBrightness, .0001f);
		        MixingWeight = min(MixingWeight, 1/*View.ReflectionEnvironmentRoughnessMixingScaleBiasAndLargestWeight.z*/);
		        return lerp(1.0f, MixingWeight, MixingAlpha);
	        }
   
            v2f vert (appdata v)
            {
                v2f o;
                o.positionOS = v.vertex;
                o.positionCS = TransformObjectToHClip(v.vertex);
                o.uv = v.uv;
                VertexPositionInputs position_inputs = GetVertexPositionInputs(v.vertex);
                VertexNormalInputs normal_inputs = GetVertexNormalInputs(v.normal, v.tangent);
                o.normalWS = normal_inputs.normalWS;
                o.tangentWS = normal_inputs.tangentWS;
                o.bitangentWS = normal_inputs.bitangentWS;
            // #if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
                o.shadowCoord = GetShadowCoord(position_inputs);
                o.vertexSH = SampleSHVertex(o.normalWS);
            // #endif
                OUTPUT_LIGHTMAP_UV(input.lightmapUV, unity_LightmapST, output.lightmapUV);
                return o;
            }

            half4 frag (v2f i) : SV_Target
            {
                float3 positionWS = TransformObjectToWorld(i.positionOS);
                half3 viewDirWS = GetCameraPositionWS() - positionWS;
                float3 cameraVector = -viewDirWS;
                float3 normalTexTS = normalize(UnpackNormal(SAMPLE_TEXTURE2D(_NormalTex, sampler_NormalTex, i.uv)));
                float3 normalWorld = TransformTangentToWorld(normalTexTS.xyz,
        half3x3(i.tangentWS.xyz, i.bitangentWS.xyz, i.normalWS.xyz));
                normalWorld = normalize(normalWorld);
                float4 MSRO = SAMPLE_TEXTURE2D(_SPColorTex, sampler_SPColorTex, i.uv);
                
                Light mainLight = GetMainLight(i.shadowCoord);
                float shiftTex = SAMPLE_TEXTURE2D(_HighlightShiftTex, sampler_HighlightShiftTex, i.uv);
                float3 hairSpecColor = HairLighting(normalize(i.tangentWS), normalize(normalWorld), normalize(mainLight.direction), normalize(viewDirWS), i.uv, MSRO.a, shiftTex);

                float3 albedo = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv) * _Color;
                float metallic = _Metallic * MSRO.r;
                float3 diffuse = albedo - albedo * metallic;
                // float3 SpecColor = 0.08 * hairSpecColor;
                // SpecColor = (SpecColor - SpecColor * metallic)+ albedo * metallic;
                half3 diffuseGI = SAMPLE_GI(input.lightmapUV, i.vertexSH, i.normalWS);
                float3 col = 0;
                float NoL = dot( normalWorld, mainLight.direction );
                NoL = max(0, NoL);
                col += albedo * diffuseGI /** MSRO.b*/;
                col += NoL * mainLight.color *  (diffuse + hairSpecColor);

                half3 reflectDir = reflect(cameraVector, i.normalWS);
                half roughness = PerceptualSmoothnessToPerceptualRoughness(MSRO.b);
                half mip = PerceptualRoughnessToMipmapLevel(roughness);
                // half4 cubeTex = SAMPLE_TEXTURECUBE_LOD(_CubeMap, sampler_CubeMap, normalize(reflectDir), mip);
                half3 cubeColor = GetImageBasedReflectionLighting(MSRO.b, MSRO.a * Luminance(SampleSH(normalWorld)), normalize(reflectDir), normalWorld);
                // cubeColor = DecodeHDREnvironment(cubeTex,unity_SpecCube0_HDR);
                // cubeColor *=cubeColor;
                // cubeColor *= MobileComputeMixingWeight(Luminance(diffuseGI), Luminance(_GlossyEnvironmentColor), 1 - MSRO.a);
                col += cubeColor * max(0, _CubeIntensity) * MSRO.g;
                return half4(col, 1);
                
                
            }
            ENDHLSL
        }
    }
}
