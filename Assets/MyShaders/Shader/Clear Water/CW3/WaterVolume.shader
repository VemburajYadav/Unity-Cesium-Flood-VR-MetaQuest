Shader "Silent/Clear Water 3 Water Volume Box"
// UNITY_SHADER_NO_UPGRADE 
{
    Properties
    {
        [HeaderEx(Underwater Fog Settings)]
		_RefractThickness("Water Thickness", Range(0, 1)) = 0.5
		_RefractTransmission("Water Transmission", Range(0, 1)) = 1
		_RefractAbsorptionScale("Water Absorption Scale", Range(0.001, 2)) = 1.0
		_RefractSurfaceCol("Surface Color Power", Range(0, 1)) = 0
		[ToggleUI]_RefractUseColor("Use Custom Absorption Color", Float) = 0
		[Gamma]_RefractColor("Custom Absorption Color", Color) = (0,0,0,1)

		[Space]
		[ToggleUI]_UseDepthFog("Depth Fog", Range(0, 1)) = 1
		[Enum(Exponential, 0, Exponential Squared, 1, Linear, 2)]
		_FogMode("Depth Fog Mode", Float) = 0
		_FogExpDensity("Depth Fog Density (Exponential)", Range(0.001, 1)) = 0.05
		_FogLinearDensity("Depth Fog Density (Linear)", Vector) = (20, 200, 0, 0)
        
        [HeaderEx(Probe Settings)]
        [NoScaleOffset]_ProbeTexture("Probe Texture Override", Cube) = "unity_SpecCube0" {}
        _BlurLevelNear("Blur Level Near (def: 4)", Range(0, 7)) = 7
        _BlurLevelFar("Blur Level Far (def: 4)", Range(0, 7)) = 4
        _BlurRange("Blur Range (def: 30)", Range(1, 1000)) = 30
        _ProbeAlpha("Probe Alpha", Range(0, 1)) = 1
        _FogColor("Fog Color Tint", Color) = (1,1,1,1)
        
        [HeaderEx(Projected Caustics)]
        [SetKeyword(_USE_CAUSTICS)][NoScaleOffset]_CausticsTex ("Caustics Texture", 2D) = "white" {}
        [IfDef(_USE_CAUSTICS)]_CausticsStrength ("Caustics Strength", Float) = 1.0
        [IfDef(_USE_CAUSTICS)]_CausticsSpeed ("Caustics Speed", Float) = 0.04
        [IfDef(_USE_CAUSTICS)]_CausticsScale ("Caustics Scale", Float) = 0.2
        [IfDef(_USE_CAUSTICS)]_CausticsMaxDistance ("Caustics Max Distance", Range(1, 1000)) = 30
    }
    SubShader
    {
        Tags 
        {  
            "Queue" = "Overlay"
            "RenderType"="Transparent"  
            "DisableBatching"="true" 
            "ForceNoShadowCasting"="True" 
            "IgnoreProjector"="True" 
        }
        Cull Front
        LOD 100

CGINCLUDE
    #pragma multi_compile_instancing
    #pragma multi_compile_fog

    #include "UnityCG.cginc"
    #include "Lighting.cginc"
    #include "AutoLight.cginc"
    #include "UnityPBSLighting.cginc"
    #include "UnityStandardUtils.cginc"

    #include "WaterUtils.hlsl"

	#include "tanoise/tanoise.cginc"
    
    
CBUFFER_START(UnityPerMaterial)
    uniform half _RefractThickness;
	uniform half _RefractTransmission;
	uniform half _RefractSurfaceCol;
	uniform half _RefractAbsorptionScale;
	uniform half _RefractUseColor;
	uniform half4 _RefractColor;
	uniform float _SurfWaveDistort;
    uniform float _UseDepthFog;
	uniform half _FogMode;
	uniform half _FogExpDensity;
	uniform half4 _FogLinearDensity;
    uniform float _ProbeAlpha;
    uniform float4 _FogColor;
    uniform float _BlurLevelNear;
    uniform float _BlurLevelFar;    
    uniform float _BlurRange;    
    UNITY_DECLARE_TEXCUBE(_ProbeTexture); uniform float4 _ProbeTexture_HDR;

    // Caustics
    
    sampler2D _CausticsTex;
    uniform float _CausticsSpeed;
    uniform float _CausticsScale;
    uniform float _CausticsStrength;
    uniform float _CausticsMaxDistance;
    uniform float _EdgeFadeRadius;
    uniform float _EdgeFadeOffset;

    sampler2D _WarpTex;
    uniform float4 _WarpTex_ST;
    uniform float4 _WarpPow;
CBUFFER_END

// https://iquilezles.org/articles/distfunctions
float sdBox( float3 p, float3 b )
{
    float3 d = abs(p) - b;
    return min(max(d.x,max(d.y,d.z)),0.0) + length(max(d,0.0));
}

float3 closestPointToBox( float3 p, float3 b )
{
    float3   d = abs(p) - b;
    float  m = min(0.0,max(d.x,max(d.y,d.z)));
    return p - float3(d.x>=m?d.x:0.0,
                    d.y>=m?d.y:0.0,
                    d.z>=m?d.z:0.0)*sign(p);
}

bool IsPointInBox(float3 testPoint, float3 boxOrigin, float3 boxScale)
{
    float3 minCorner = boxOrigin - boxScale * 0.5;
    float3 maxCorner = boxOrigin + boxScale * 0.5;
    return all(testPoint >= minCorner) && all(testPoint <= maxCorner);
}

#if defined(_USE_CAUSTICS)
float3 getCausticProjected(float3 worldPosition, float edgeFadeMask, float distFade)
{
	float4 noise = tanoise4(float4(worldPosition + _SinTime.xyz + _CosTime.zyx, _Time.x));

	float3 posToLight = normalize(_WorldSpaceLightPos0.xyz - worldPosition);

	float3 causticsPos = dot(worldPosition + noise, posToLight) * posToLight * _CausticsScale;
	causticsPos.xy = 0.5 * causticsPos.xz + causticsPos.y * 0.1;
	
    float2 uv1 = causticsPos + _Time.y * _CausticsSpeed;
    float2 uv2 = causticsPos * -1.0 + _Time.y * _CausticsSpeed * 0.5;

    float3 causticstex = tex2Dlod(_CausticsTex, float4(uv1,0, distFade*7)).rgb;
    float3 causticstex2 = tex2Dlod(_CausticsTex, float4(uv2,0, distFade*7)).rgb;

    float3 caustics = min(causticstex, causticstex2) * edgeFadeMask;
    return caustics;
}
#endif

struct appdata
{
	UNITY_VERTEX_INPUT_INSTANCE_ID
    float4 vertex : POSITION;
};

struct v2f
{
	UNITY_VERTEX_INPUT_INSTANCE_ID
    float4 vertex : SV_POSITION;
    float4 worldPos : WORLDPOS;
    float2 screenPosition : SCREENPOS;
    float3 localCameraPos : CAMERAPOS;
    UNITY_VERTEX_OUTPUT_STEREO
};

v2f vert (appdata v)
{
    v2f o;
    
    UNITY_SETUP_INSTANCE_ID(v); 
    UNITY_INITIALIZE_OUTPUT(v2f, o); 
    UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o); 

    o.vertex = UnityObjectToClipPos(v.vertex);
    o.worldPos.xyz = mul(unity_ObjectToWorld, v.vertex).xyz;
    
    fixed3 baseWorldPos = unity_ObjectToWorld._m03_m13_m23;
    fixed3 worldScale = (float3(unity_ObjectToWorld[0].x, unity_ObjectToWorld[1].x, unity_ObjectToWorld[2].x));

    // local space position of the camera to check against box in local space so we don't need to use rotation etc               
    float3 localCameraPos = mul(unity_WorldToObject, _WorldSpaceCameraPos.xyz - unity_ObjectToWorld._m03_m13_m23);
    bool isVisible = IsPointInBox(localCameraPos, 0.0, 1.0);
    o.worldPos.w = isVisible;
    o.localCameraPos = localCameraPos;

    // if we're outside the box, set vertex pos to discard
    if (!isVisible) o.vertex.z = 1e+9;

    // Save the clip space position so we can use it later.
    // This also handles situations where the Y is flipped.
    float2 suv = o.vertex * float2( 0.5, 0.5*_ProjectionParams.x);
                            
    // Tricky, constants like the 0.5 and the second paramter
    // need to be premultiplied by o.vertex.w.
    o.screenPosition = TransformStereoScreenSpaceTex( suv+0.5*o.vertex.w, o.vertex.w );
    return o;
}

float4 fragBase(v2f i, const bool isAddPass)
{
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX( i );
    
    // Common data calculation here
    float3 fullVectorFromEyeToGeometry = i.worldPos - _WorldSpaceCameraPos;
    float3 worldSpaceDirection = normalize( i.worldPos - _WorldSpaceCameraPos );

    float perspectiveDivide = 1.0f / i.vertex.w;
    float perspectiveFactor = length( fullVectorFromEyeToGeometry * perspectiveDivide );

    // Calculate our UV within the screen (for reading depth buffer)
    float2 screenUV = i.screenPosition.xy * perspectiveDivide;
    float eyeDepthWorld =
        GetLinearZFromZDepth_WorksWithMirrors( 
            SAMPLE_DEPTH_TEXTURE( _CameraDepthTexture, screenUV), 
            screenUV ) * perspectiveFactor;
            
    // eyeDepthWorld is in meters.
    float sceneDepthZeroOne = saturate(eyeDepthWorld / _ProjectionParams.z);

    float3 worldPosEyeHitInDepthTexture = _WorldSpaceCameraPos + eyeDepthWorld * worldSpaceDirection;
    float radialDepth = distance(_WorldSpaceCameraPos, worldPosEyeHitInDepthTexture);    
    
    // Clamp fog against box boundary
    float boxDepth = boxDensity(_WorldSpaceCameraPos, worldSpaceDirection, unity_WorldToObject, 0.5, eyeDepthWorld);
    boxDepth = saturate(boxDepth*5);
    
    // Air's Index of refraction is 1.000277 at STP but everybody uses 1.0
    const float airIor = 1.0;
    // Water's IOR is 1.333. This is water, right? 
    float materialor = 1.333;
    float etaIR = airIor / materialor;  // air -> material
    float etaRI = materialor / airIor;  // material -> air

    float3 waterAbsorption = float3(0.811f, 0.0067f, 0.00166f);
    waterAbsorption = _RefractUseColor? (1.0 - _RefractColor) : waterAbsorption;

    // Fudge factor to make shadow water less absorbing. 
    float thicknessApproxByDistance = saturate(radialDepth);
    float absorptionUserTweak = 1.0f / _RefractAbsorptionScale;

    // Should they be user-controllable?
    //float refrTransmission = _RefractTransmission; // How visible the refraction is. def 1.0
    float3 refrAbsorption = waterAbsorption * radialDepth * absorptionUserTweak; // What colour gets absorbed by the medium. 
    float refrThickness = _RefractThickness * thicknessApproxByDistance; // Thicker materials distort more. def 0.5

    float3 T = exp(-refrAbsorption * eyeDepthWorld);
    float fogFac = 1.0;

    if (_UseDepthFog)
    {
        switch (_FogMode)
        {
            case 0: fogFac = exp2(-_FogExpDensity * eyeDepthWorld); break;
            case 1: fogFac = exp2(-_FogExpDensity * _FogExpDensity * eyeDepthWorld); break;
            case 2: fogFac = ( (_FogLinearDensity.y - eyeDepthWorld) / (_FogLinearDensity.y - _FogLinearDensity.x) ); break;
        };
    }

    float3 col = 1.0;

    // The fog is performed in two passes, because we have no way to apply colour multiplication 
    // and addition in one pass... (outside of using a GrabPass) 

    T = lerp(0, T, fogFac);

    if (isAddPass)
    {
        float fogDistance = (length(worldSpaceDirection.xyz * eyeDepthWorld));

        float blurLevelRange = saturate(eyeDepthWorld / _BlurRange);
        float blurLevel = lerp(_BlurLevelNear, _BlurLevelFar, blurLevelRange);
        
        float4 probeCol = UNITY_SAMPLE_TEXCUBE_LOD( _ProbeTexture, worldSpaceDirection, blurLevel);
        probeCol = float4(DecodeHDR(probeCol, _ProbeTexture_HDR), 1.0);
        probeCol = lerp(1, probeCol, _ProbeAlpha) * _FogColor;

        col = probeCol * pow((1.0 - waterAbsorption), 40) * dot(1.0 - T, 0.333);

        // fade to 0
        col *= boxDepth;
    }
    else
    {
        // fade to 1
        col = lerp(1.0, T, boxDepth);
    }
    
    #if defined(_USE_CAUSTICS)

        float edgeFadeMask = causticsEdgeFadeMask(worldPosEyeHitInDepthTexture, _EdgeFadeOffset, _EdgeFadeRadius) * fogFac;

        float causticsDistFade = saturate(eyeDepthWorld / _CausticsMaxDistance);
        float3 caustics = getCausticProjected(worldPosEyeHitInDepthTexture, edgeFadeMask, causticsDistFade);

        
            if (isAddPass)
            {
                // Nothing
            }
            else
            {
                col += caustics * _CausticsStrength * _LightColor0.xyz * fogFac * T;
            }
    #endif

    float alpha = 0;

    return float4(col, alpha);

}

ENDCG

Pass
{
    // Don't write alpha, and don't write depth
    ColorMask RGB
    ZWrite Off
    Lighting Off
    ZTest Off
    // Multiply blend (reduce to zero)
    Blend DstColor Zero  // or SrcColor

    CGPROGRAM
    #pragma vertex vert
    #pragma fragment frag
	#pragma shader_feature_local _USE_CAUSTICS

    float4 frag (v2f i) : SV_Target
    {
        UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX( i );
        return fragBase(i, false);
    }
    ENDCG
}

Pass
{
    ColorMask RGB
    ZWrite Off
    Lighting Off
    ZTest Off
    // Additive blend (no point in using alpha, BG is already black)
    Blend One One 

    CGPROGRAM
    #pragma vertex vert
    #pragma fragment frag
	#pragma shader_feature_local _USE_CAUSTICS

    float4 frag (v2f i) : SV_Target
    {
        UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX( i );
        return fragBase(i, true);
    }
    ENDCG
    
}
    }
}
