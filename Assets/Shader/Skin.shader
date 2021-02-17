Shader"14/Skin"
{
    Properties
    {
        [KeywordEnum(Skin, Face, Stocking)]_Type("Type", Float) = 0
        
        [Header(Skin)]
        [HDR]_Color("Color", Color) = (0.85,0.75,0.75,1)
        _MainTex ("Albedo", 2D) = "white" {}
        _NormalTex("Normal Tex", 2D) = "Bump" {}
        _RimMaskTex("Rim Mask Tex", 2D) = "white" {}
        [HDR]_RimColor("Rim Color", Color) = (0.7,0.2,0.17,1)
        _RimFalloff("Rim Falloff", Range(0,10)) = 2
        _ShadowStr("ShadowStr", Range(0,1)) = 0.75
        _FacePlane("FacePlane", Float) = 1
        _BandWidth("BandWidth", Range(0,1))=0.15
        _LightIndirectAtten("Light Indirect Atten",Range(0,1)) = 0.5
        _HighLightFalloff("HighLightFalloff", float) = 20
        [HDR]_HighLightColor("HighLightColor", Color) = (1,1,1,1)
        
        [Header(Stocking)]
        _WeaveMask("WeaveMask", 2D) = "black"{}
        _NormalStr("NormalStr", Float) = 1.5
        _FresnelRatio("FresnelRatio", Range(0,5)) = 1
        _FresnelStart("FresnelStart", Range(0,1)) = 0.5
        [HDR]_StockingColor("StockingColor", Color) = (0,0,0,1)
        
//        [Header(Outline)]
//        _OutlineColor("OutlineColor", Color) = (1,1,1,1)
        
    }
    SubShader
    {
        Tags 
        { 
            "RenderType"="Transparent" 
            "LightMode" = "UniversalForward"
        }
        LOD 100
            
        Pass
        {
//            Blend SrcAlpha OneMinusSrcAlpha
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma shader_feature _RECEIVE_SHADOWS_OFF
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _SHADOWS_SOFT
            #pragma multi_compile _ LIGHTMAP_ON
            #pragma multi_compile _ _TYPE_FACE _TYPE_STOCKING
            // #pragma multi_compile _ _ADDITIONAL_LIGHTS
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            // #include "AddLighting.hlsl"

            struct appdata
            {
                float4 vertex : POSITION;
                float4 normal : NORMAL;
                float4 tangent : TANGENT;
                float4 color : COLOR;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float4 vertex : SV_POSITION;
                float4 vertexColor : COLOR;
                float2 uv : TEXCOORD0;
                float3 tangentWS : TEXCOORD1;
                float3 bitangentWS : TEXCOORD2;
                float3 normalWS : TEXCOORD3;
                float3 positionWS : TEXCOORD4;
                float4 shadowCoord : TEXCOORD5;
                float3 vertexSH : TEXCOORD6;
                float3 normalWSOS : TEXCOORD7;
            };

            Texture2D _MainTex;
            SamplerState sampler_MainTex;
            Texture2D _NormalTex;
            SamplerState sampler_NormalTex;
            Texture2D _RimMaskTex;
            SamplerState sampler_RimMaskTex;
        #if _TYPE_STOCKING
            Texture2D _WeaveMask;
            SamplerState sampler_WeaveMask;
        #endif
            
            CBUFFER_START(UnityPerMaterial)
            float3 _Color;
            float4 _RimColor;
            float _RimFalloff;
            float _ShadowStr;
            float3 _HighLightColor;
            float _HighLightFalloff;
            float _FacePlane;
            float _LightIndirectAtten;
            float _BandWidth;
            half _SSStr;

            float4 _FabricScatterColor;
            float _FabricPow;
            float _NormalStr;
            float _FresnelRatio;
            float _FresnelStart;
            float3 _StockingColor;
            float4 _WeaveMask_ST;
            CBUFFER_END

            float3 Curve(float3 color, float k)
            {
	            return exp(log(max(color, int3(0, 0, 0))) * k);
            }
            half Fabric(half VdN)
            {
                half intensity = 1 - VdN;
                intensity = 0 - (intensity * 0.4 - pow(intensity, _RimFalloff) ) * 0.35;
                return saturate(intensity);
            }
            half StockingAlpha(half weavingMask, half NdV, half2 uv)
            {
                half rNdV = NdV * NdV;
                half rim = saturate(((1 - clamp(rNdV, 0, 1) ) * _FresnelRatio + _FresnelStart));
                rim = clamp(rim,0, 1);
                half mask = rNdV * weavingMask;
                mask = rim - mask * rim;
                return saturate(mask);
            }

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = TransformObjectToHClip(v.vertex);
                o.uv = v.uv;
                o.vertexColor = v.color;
                VertexPositionInputs vertex_position_inputs = GetVertexPositionInputs(v.vertex);
                VertexNormalInputs defaultNormal = GetVertexNormalInputs(v.normal);
                o.normalWSOS.xyz = defaultNormal.normalWS;
                v.normal.z *= max(0.1,_FacePlane);
                VertexNormalInputs vertex_normal_inputs = GetVertexNormalInputs(v.normal);
                o.tangentWS = vertex_normal_inputs.tangentWS;
                o.bitangentWS = vertex_normal_inputs.bitangentWS;
                o.normalWS = vertex_normal_inputs.normalWS;
                o.positionWS = vertex_position_inputs.positionWS;
                o.shadowCoord = GetShadowCoord(vertex_position_inputs);
                OUTPUT_LIGHTMAP_UV(v.lightmapUV, unity_LightmapST, o.lightmapUV);
                o.vertexSH = SampleSHVertex(o.normalWS);
                return o;
            }

            half4 frag (v2f i) : SV_Target
            {
                half rimMask = SAMPLE_TEXTURE2D(_RimMaskTex, sampler_RimMaskTex, i.uv);
                // return half4(i.normalWS,1);
            #ifdef _TYPE_FACE
                half3 normalWS = normalize(i.normalWS);
            #else
                half3 normalTex = UnpackNormal(SAMPLE_TEXTURE2D(_NormalTex, sampler_NormalTex, i.uv));
                half3 normalWS = mul(normalTex,half3x3(i.tangentWS, i.bitangentWS, i.normalWS));
                normalWS = normalize(normalWS);
            #endif
                
                half3 viewDirWS = i.positionWS - GetCameraPositionWS();
                 //Light
                Light mainLight = GetMainLight(i.shadowCoord);
                half3 lightDirWS = mainLight.direction;
                half ndl = dot(normalWS, lightDirWS);
                half shadowAtten = mainLight.shadowAttenuation * _ShadowStr + 1-_ShadowStr;
                half lightAtten = max(0,ndl);
                
                half4 albedo = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv)* half4(_Color,1);

                half3 baseColor = albedo.rgb;

                //nose
                half ndv;
            #ifdef _TYPE_STOCKING
                ndv = saturate(dot(normalWS, -normalize(viewDirWS)));
                half weaveMask = max(0, SAMPLE_TEXTURE2D(_WeaveMask, sampler_WeaveMask, i.uv * _WeaveMask_ST.xy + _WeaveMask_ST.zw) * _NormalStr);
                half shade = lerp(0, ndl * 0.5 + 0.5, shadowAtten);
                half stockingFabric = Fabric(ndv) * clamp(shade, 0.5, 1);
                half stockingAlpha = StockingAlpha(weaveMask, ndv, i.uv);
                half highlight = saturate(1-stockingAlpha) * half4(Curve(ndv.xxx,15),1);
                baseColor = baseColor * (1-stockingAlpha)+_StockingColor * stockingAlpha + highlight*0.05;
                baseColor = lerp(baseColor, _RimColor, stockingFabric);
            #else
                ndv = saturate(dot(TransformObjectToWorldDir(half4(0,0,1,1)), -normalize(viewDirWS)));
                // baseColor = lerp(baseColor, baseColor + albedo.a, albedo.a * ndv);
            #endif
                
                
                half3 bakedGI = SAMPLE_GI(input.lightmapUV, i.vertexSH, i.normalWS);
                half3 col = baseColor * bakedGI * 0.2 + baseColor * 0.8;
                
                //**************** Rim
            #ifdef _TYPE_STOCKING
            #elif _TYPE_FACE
                half ndvO = dot(normalize(normalWS), -normalize(viewDirWS));
                half rim = Curve(saturate(pow(saturate(1-ndvO), _RimFalloff)), 15) * rimMask * ndv;
                col = lerp(col, _RimColor, saturate(rim) * _RimColor.a+ (1-mainLight.shadowAttenuation )* _SSStr);
            #else
                half ndvO = dot(normalize(i.normalWS), -normalize(viewDirWS));
                half rim =(saturate(pow(saturate(1-ndvO), _RimFalloff))) * rimMask;
                col = lerp(col, _RimColor, saturate(rim) * _RimColor.a + (1-mainLight.shadowAttenuation )* _SSStr);
            #endif
                
                //**************** dirLight
                lightAtten *= shadowAtten;
                lightAtten = smoothstep(0,_BandWidth,lightAtten)/**0.5*/;
                lightAtten = lerp(0, lightAtten, _LightIndirectAtten);
                half3 dirLightCol = saturate(lightAtten) * mainLight.color * baseColor;
                col += dirLightCol;
                
                
                //**************** addlight
            #ifdef _ADDITIONAL_LIGHTS
                uint pixelLightCount = GetAdditionalLightsCount();
                for (uint lightIndex = 0u; lightIndex < pixelLightCount; ++lightIndex)
                {
                    Light light = GetAdditionalLight(lightIndex, i.positionWS);
                    half3 addLightDirWS = light.direction;
                    half addNdl = dot(normalWS, addLightDirWS);
                    half addLightAtten = max(0,addNdl) * light.distanceAttenuation;
                    half addShadowAtten = light.shadowAttenuation * _ShadowStr + 1-_ShadowStr;
                    addLightAtten *= addShadowAtten;
                    addLightAtten = smoothstep(0,_BandWidth,addLightAtten)/**0.5*/;
                    addLightAtten = _LightIndirectAtten * addLightAtten + (1 - _LightIndirectAtten)/2;
                    half3 addLightCol = saturate(addLightAtten) * light.color * baseColor;
                    col += addLightCol;
                }
            #endif

            #ifdef _ADDITIONAL_LIGHTS_VERTEX
                color += inputData.vertexLighting * brdfData.diffuse;
            #endif

                               
                //**************** staticHighLight
                // return i.normalWSOS.w;
            #ifdef _TYPE_FACE
                half staticatten = dot(i.normalWSOS.xyz, normalize(-cross(viewDirWS,UNITY_MATRIX_V[1])))  /** rimMask*/ * ndv;
            #else
                half staticatten = dot(i.normalWSOS.xyz, normalize(-cross(viewDirWS,UNITY_MATRIX_V[1])))  /** rimMask*/ ;
            #endif
                half3 staticLight = Curve(Smootherstep01(staticatten), max(0.001, _HighLightFalloff)) * _HighLightColor;
                col += staticLight;

                //**************** shadow
                // half shadowAtten = mainLight.shadowAttenuation;
                // shadowAtten = 1 - shadowAtten;
                // half3 shadowSubColor = 1 - _ShadowColor;
                // col -= shadowAtten * shadowSubColor * _ShadowStr /** (1-UltraTex.r)*/;


                //***************** GI
                // BRDFData brdfData;  
                // half smoothness = pow(1 - UltraTex.r, 2);
                // InitializeBRDFData(/*col*/baseColor, 0.08, 0, smoothness, 1, brdfData);
                // MixRealtimeAndBakedGI(mainLight, normalWS, bakedGI, half4(0, 0, 0, 0));
                // half3 GI = GlobalIllumination(brdfData, bakedGI, 1, normalWS, viewDirWS);
                // col += GI * 0.08;


                return half4(saturate(col),albedo.a);
            }
            ENDHLSL
        }

        Pass
        {
            Name "Outline"
            Tags{"LightMode" = "Outline"}

            ZWrite Off
            Cull Front

            HLSLPROGRAM
            // Required to compile gles 2.0 with standard srp library
            #pragma prefer_hlslcc gles
            #pragma exclude_renderers d3d11_9x
            #pragma target 2.0

            //--------------------------------------
            // GPU Instancing
            #pragma multi_compile_instancing

            #pragma vertex OutlineVertex
            #pragma fragment OutlineFragment

            #include "Outline.hlsl"
            ENDHLSL
        }
        
        Pass
        {
            Name "ShadowCaster"
            Tags{"LightMode" = "ShadowCaster"}

            ZWrite On
            ZTest LEqual
            Cull[_Cull]

            HLSLPROGRAM
            // Required to compile gles 2.0 with standard srp library
            #pragma prefer_hlslcc gles
            #pragma exclude_renderers d3d11_9x
            #pragma target 2.0

            // -------------------------------------
            // Material Keywords
            #pragma shader_feature _ALPHATEST_ON

            //--------------------------------------
            // GPU Instancing
            #pragma multi_compile_instancing
            #pragma shader_feature _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A

            #pragma vertex ShadowPassVertex
            #pragma fragment ShadowPassFragment

            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/ShadowCasterPass.hlsl"
            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags{"LightMode" = "DepthOnly"}

            ZWrite On
            ColorMask 0
            Cull[_Cull]

            HLSLPROGRAM
            // Required to compile gles 2.0 with standard srp library
            #pragma prefer_hlslcc gles
            #pragma exclude_renderers d3d11_9x
            #pragma target 2.0

            #pragma vertex DepthOnlyVertex
            #pragma fragment DepthOnlyFragment

            // -------------------------------------
            // Material Keywords
            #pragma shader_feature _ALPHATEST_ON
            #pragma shader_feature _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A

            //--------------------------------------
            // GPU Instancing
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/DepthOnlyPass.hlsl"
            ENDHLSL
        }

        // This pass it not used during regular rendering, only for lightmap baking.
        Pass
        {
            Name "Meta"
            Tags{"LightMode" = "Meta"}

            Cull Off

            HLSLPROGRAM
            // Required to compile gles 2.0 with standard srp library
            #pragma prefer_hlslcc gles
            #pragma exclude_renderers d3d11_9x

            #pragma vertex UniversalVertexMeta
            #pragma fragment UniversalFragmentMeta

            #pragma shader_feature _SPECULAR_SETUP
            #pragma shader_feature _EMISSION
            #pragma shader_feature _METALLICSPECGLOSSMAP
            #pragma shader_feature _ALPHATEST_ON
            #pragma shader_feature _ _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A

            #pragma shader_feature _SPECGLOSSMAP

            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitMetaPass.hlsl"

            ENDHLSL
        }
    }
}
