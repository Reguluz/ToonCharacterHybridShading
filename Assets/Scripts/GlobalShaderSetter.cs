using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;

[ExecuteInEditMode]
public class GlobalShaderSetter : MonoBehaviour
{
    public Color outlineColor;
    [Range(0, 1)] public float ignoreDistance;
    public float outlineWidth;
    public int outlineViewFade;
    public float indirectLightingColorScale = 0.2f;
    [Range(0,1)]public float CharacterSSStr = 0.2f;
    private static readonly int STATIC_OutlineColor = Shader.PropertyToID("_OutlineColor");
    private static readonly int STATIC_IgnoreDistance = Shader.PropertyToID("_IgnoreDistance");
    private static readonly int STATIC_OutlineWidth = Shader.PropertyToID("_OutlineWidth");
    private static readonly int STATIC_OutlineViewFade = Shader.PropertyToID("_OutlineViewFade");
    private static readonly int IndirectLightingColorScale = Shader.PropertyToID("_IndirectLightingColorScale");
    private static readonly int SsStr = Shader.PropertyToID("_SSStr");

    private void Update()
    {
        Shader.SetGlobalColor(STATIC_OutlineColor, outlineColor);
        Shader.SetGlobalFloat(STATIC_IgnoreDistance, ignoreDistance);
        Shader.SetGlobalFloat(STATIC_OutlineWidth, outlineWidth);
        Shader.SetGlobalInt(STATIC_OutlineViewFade, outlineViewFade);
        Shader.SetGlobalFloat(IndirectLightingColorScale, Mathf.Clamp01(indirectLightingColorScale));
        Shader.SetGlobalFloat(SsStr, CharacterSSStr);
    }
}
