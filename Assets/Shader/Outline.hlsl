#ifndef CUSTOM_OUTLINE_INCLUDED
#define CUSTOM_OUTLINE_INCLUDED
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

CBUFFER_START(UnityPerMaterial)
half4 _OutlineColor;
half _IgnoreDistance;
half _OutlineWidth;
half _OutlineViewFade;
CBUFFER_END

struct Attributes{
   half3 positionOS : POSITION;
   half3 normalOS : NORMAL;
   UNITY_VERTEX_INPUT_INSTANCE_ID
};
struct Varyings {
   half4 positionCS : SV_POSITION;
   UNITY_VERTEX_INPUT_INSTANCE_ID
};
Varyings OutlineVertex(Attributes input)
{
   Varyings output;
   half3 positionWS = TransformObjectToWorld(input.positionOS);
   output.positionCS = TransformWorldToHClip(positionWS);
   half3 normalWS = TransformObjectToWorldNormal(input.normalOS);
   half3 normalCS = TransformWorldToHClipDir(normalWS);
   half ndv = dot(normalize(normalWS), normalize(GetCameraPositionWS() - positionWS));
   half3 dir =  _OutlineWidth * normalize(normalCS) * 0.01 * saturate(pow((1-ndv), _OutlineViewFade));
   output.positionCS.xyz = output.positionCS.xyz + lerp(dir, dir * output.positionCS.w, _IgnoreDistance);
   return output;
}
float4 OutlineFragment(Varyings input) : SV_TARGET
{
   return _OutlineColor;
}
#endif