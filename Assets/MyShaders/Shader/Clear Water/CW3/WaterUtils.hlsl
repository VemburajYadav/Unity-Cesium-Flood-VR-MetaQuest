#ifndef WATER_UTILS
#define WATER_UTILS

// Generic helper functions

#define MEDIUMP_FLT_MAX    65504.0
#define MEDIUMP_FLT_MIN    0.00006103515625

#ifdef TARGET_MOBILE
#define FLT_EPS            MEDIUMP_FLT_MIN
#define saturateMediump(x) min(x, MEDIUMP_FLT_MAX)
#else
#define FLT_EPS            1e-5
#define saturateMediump(x) x
#endif

float4 testOutput(float4 x, bool alpha) { return float4(alpha?x.www:x.xyz, 1.0);}
float4 testOutput(float3 x) { return float4(x, 1.0);}
float4 testOutput(float2 x) { return float4(x.xy, 0.0, 1.0);}
float4 testOutput(float x) { return float4(x.xxx, 1.0);}

#define COHERENT_CONDITION(condition) ((condition) || any(fwidth(condition)))

float smootherstep(float a, float b, float t) 
{
    t = saturate( ( t - a ) / ( b - a ) );
    return t * t * t * (t * (t * 6. - 15.) + 10.);
}

float CalcMipLevel( float2 texture_coord )
{
	float2 dx = ddx(texture_coord);
	float2 dy = ddy(texture_coord);
	float delta_max_sqr = max(dot(dx, dx), dot(dy, dy));
	
	return max(0.0, 0.5 * log2(delta_max_sqr));
}

half4 LerpWhite4To(half4 b, half t)
{
    half oneMinusT = 1 - t;
    return half4(oneMinusT, oneMinusT, oneMinusT, oneMinusT) + b * t;
}
// Noise helper functions

uniform sampler2D _Noise; uniform float4 _Noise_TexelSize;

// n must not be normalize (e.g. window coordinates)
float interleavedGradientNoise(float2 n) {
    return frac(52.982919 * frac(dot(float2(0.06711, 0.00584), n)));
};

float RDitherPattern( float2 pixel )
{
	    const float a1 = 0.75487766624669276;
	    const float a2 = 0.569840290998;
	    return frac(a1 * float(pixel.x) + a2 * float(pixel.y));
}

// Triangular distribution
float T( float z )
{
	return z >= 0.5 ? 2.-2.*z : 2.*z;
}

float noiseTexture(float t)
{
    return tex2D(_Noise,float2(t,0)/_Noise_TexelSize.zw).x;
}
float noiseTexture(float2 t)
{
    return tex2D(_Noise,t/_Noise_TexelSize.zw).x;
}

float noiseSwitched(float2 t)
{
    // Sampling a lookup texture for blue noise
    // Coords must be aligned to a pixel boundary when sampling the texture
    float2 noiseCoord = t + floor(_Time.y * _Noise_TexelSize.zw);
    noiseCoord *= _Noise_TexelSize.xy;
    float4 noise = tex2D(_Noise, noiseCoord);
    int no = (_Time.y % (1.0/8.0))*32;
    return noise[no];
}

// Grass helper functions

// Calculate a 4 fast sine-cosine pairs
// val:     the 4 input values - each must be in the range (0 to 1)
// s:       The sine of each of the 4 values
// c:       The cosine of each of the 4 values
void FastSinCos (float4 val, out float4 s, out float4 c) 
{
    val = val * 6.408849 - 3.1415927;
    // powers for taylor series
    float4 r5 = val * val;                  // wavevec ^ 2
    float4 r6 = r5 * r5;                        // wavevec ^ 4;
    float4 r7 = r6 * r5;                        // wavevec ^ 6;
    float4 r8 = r6 * r5;                        // wavevec ^ 8;

    float4 r1 = r5 * val;                   // wavevec ^ 3
    float4 r2 = r1 * r5;                        // wavevec ^ 5;
    float4 r3 = r2 * r5;                        // wavevec ^ 7;


    //Vectors for taylor's series expansion of sin and cos
    float4 sin7 = {1, -0.16161616, 0.0083333, -0.00019841};
    float4 cos8  = {-0.5, 0.041666666, -0.0013888889, 0.000024801587};

    // sin
    s =  val + r1 * sin7.y + r2 * sin7.z + r3 * sin7.w;

    // cos
    c = 1 + r5 * cos8.x + r6 * cos8.y + r7 * cos8.z + r8 * cos8.w;
}

void WaveGrass (inout float4 vertex, float4 waveParams, float waveAmount)
{
	// Setup to compensate for missing terrain data
    // Apply wind
	waveParams.x += _Time.x * waveParams.w;

    float4 _waveXSize = float4(0.012, 0.02, 0.06, 0.024) * waveParams.y;
    float4 _waveZSize = float4 (0.006, .02, 0.02, 0.05) * waveParams.y;
    float4 waveSpeed = float4 (0.3, .5, .4, 1.2) * 4;

    float4 _waveXmove = float4(0.012, 0.02, -0.06, 0.048) * 2;
    float4 _waveZmove = float4 (0.006, .02, -0.02, 0.1);

    float4 waves;
    waves = vertex.x * _waveXSize;
    waves += vertex.z * _waveZSize;

    // Add in time to model them over time
    waves += waveParams.x * waveSpeed;

    float4 s, c;
    waves = frac (waves);
    FastSinCos (waves, s,c);

    s = s * s;

    s = s * s;

    s = s * waveAmount;

    float3 waveMove = float3 (0,0,0);
    waveMove.x = dot (s, _waveXmove);
    waveMove.z = dot (s, _waveZmove);

    vertex.xz -= waveMove.xz * waveParams.z;
}

float3 softClamp(float3 x, float amount)
{
	return (x * (amount + 1)) / (x + amount);
}

inline float2 applyScaleOffset(float2 uv, float4 scaleOffset)
{
    return uv * scaleOffset.xy + scaleOffset.zw;
}

void TrembleGrass(inout float4 worldPosition, float3 vertex, float3 normal, float waveAmount)
{
	// Neat snipped based on method in Guerrilla Games – GDC 2018 – Between Tech and Art: The Vegetation of Horizon Zero Dawn
	float3 displacement = (0.065 * sin(2.650 * (vertex.x + vertex.y + vertex.z + _Time.y)))
		* float3(1, 1, 0.35) * normal;
	worldPosition.xyz += displacement * waveAmount;
}

// Shading helper functions

float3 gtaoMultiBounce(float visibility, const float3 albedo) {
    // Jimenez et al. 2016, "Practical Realtime Strategies for Accurate Indirect Occlusion"
    float3 a =  2.0404 * albedo - 0.3324;
    float3 b = -4.7951 * albedo + 0.6417;
    float3 c =  2.7552 * albedo + 0.6903;

    return max(visibility, ((visibility * a + b) * visibility + c) * visibility);
}

float SpecularAO_Lagarde(float NoV, float visibility, float roughness) {
    // Lagarde and de Rousiers 2014, "Moving Frostbite to PBR"
    return saturate(pow(NoV + visibility, exp2(-16.0 * roughness - 1.0)) - 1.0 + visibility);
}

float computeMicroShadowing(float NoL, float visibility) {
    // Chan 2018, "Material Advances in Call of Duty: WWII"
    float aperture = rsqrt(1.0 - visibility);
    float microShadow = saturate(NoL * aperture);
    return microShadow * microShadow;
};

float IsotropicNDFFiltering(float3 normal, float roughness2) {
    // Tokuyoshi and Kaplanyan 2021, "Stable Geometric Specular Antialiasing with
	// Projected-Space NDF Filtering"
	float SIGMA2 = 0.15915494;
	float KAPPA = 0.18;
	float3 dndu = ddx(normal);
	float3 dndv = ddy(normal);
	float kernelRoughness2 = 2.0 * SIGMA2 * (dot(dndu, dndu) + dot(dndv, dndv));
	float clampedKernelRoughness2 = min(kernelRoughness2, KAPPA);
	float filteredRoughness2 = saturate(roughness2 + clampedKernelRoughness2);
	return filteredRoughness2;
}
float pow5(float x)
{
    float x2 = x * x;
    return x2 * x2 * x;
}

float sq(float x)
{
    return x * x;
}


half3 F_Schlick(half u, half3 f0)
{
    return f0 + (1.0 - f0) * pow(1.0 - u, 5.0);
}

float F_Schlick(float f0, float f90, float VoH)
{
    return f0 + (f90 - f0) * pow5(1.0 - VoH);
}

half D_GGX(half NoH, half roughness)
{
    half a = NoH * roughness;
    half k = roughness / (1.0 - NoH * NoH + a * a);
    return k * k * (1.0 / UNITY_PI);
}

half V_SmithGGXCorrelatedFast(half NoV, half NoL, half roughness) {
    half a = roughness;
    float GGXV = NoL * (NoV * (1.0 - a) + a);
    float GGXL = NoV * (NoL * (1.0 - a) + a);
    return 0.5 / (GGXV + GGXL);
}

half V_SmithGGXCorrelated(half NoV, half NoL, half roughness)
{
    #ifdef SHADER_API_MOBILE
    return V_SmithGGXCorrelatedFast(NoV, NoL, roughness);
    #else
    half a2 = roughness * roughness;
    float GGXV = NoL * sqrt(NoV * NoV * (1.0 - a2) + a2);
    float GGXL = NoV * sqrt(NoL * NoL * (1.0 - a2) + a2);
    return 0.5 / (GGXV + GGXL);
    #endif
}

float4 UnityLightmap_ColorIntensitySeperated(float3 lightmap) {
    lightmap += 0.000001;
    return float4(lightmap.xyz / 1, 1);
}

struct SSSParams
{
	float distortion;
	float power;
	float scale;
	float ambient;
	float shadowStrength;
	// Not part of GI data passed to BRDF
	float lightAttenuation; 
};

float3 getSubsurfaceScatteringLight (SSSParams data, float3 lightDir, float3 normalDirection, float3 viewDirection, 
    float3 thickness)
{
    float3 vSSLight = lightDir + normalDirection * data.distortion;
    float3 vdotSS = pow(saturate(dot(viewDirection, -vSSLight)), data.power) 
        * data.scale; 
	float sssAttenuation = lerp(1, data.lightAttenuation, data.shadowStrength * float(any(_WorldSpaceLightPos0.xyz)));
    
    return 	sssAttenuation * (vdotSS + data.ambient) * thickness;
}

// Depth helper functions

uniform UNITY_DECLARE_DEPTH_TEXTURE(_CameraDepthTexture); uniform float4 _CameraDepthTexture_TexelSize;

float4 screenDepthClamped(float2 screenUV)
{
	// Sample the depth texture clamped to texel centres.
	screenUV = (floor(screenUV * _CameraDepthTexture_TexelSize.zw) + 0.5) *
		abs(_CameraDepthTexture_TexelSize.xy);
	return SAMPLE_DEPTH_TEXTURE( _CameraDepthTexture, screenUV);
}

float GetLinearZFromZDepth_WorksWithMirrors(float zDepthFromMap, float2 screenUV) {
    #if defined(UNITY_REVERSED_Z)
        zDepthFromMap = 1 - zDepthFromMap;
    #endif
    if( zDepthFromMap >= 1.0 ) return _ProjectionParams.z;
    float4 clipPos = float4(screenUV.xy, zDepthFromMap, 1.0);
    clipPos.xyz = 2.0f * clipPos.xyz - 1.0f;
    float2 camPos = mul(unity_CameraInvProjection, clipPos).zw;
    return -camPos.x / camPos.y;
}

uniform float _VRChatMirrorMode;
bool isInMirror()
{
	return  _VRChatMirrorMode != 0;
    // return (asuint(unity_CameraProjection[2][0]) || asuint(unity_CameraProjection[2][1]));
}

bool isDepthAvailable()
{
    bool hasDepth = dot(_CameraDepthTexture_TexelSize.xy, 1.0) > 32;
    return hasDepth || isInMirror();
}


// Based on Tuxalin's water shader; https://github.com/tuxalin/water-shader
struct depthRefractionParams
{
	// Affects how fast the colors will fade out, thus, use smaller values (eg. 0.05f).
	// to have crystal clear water and bigger to achieve "muddy" water.
	float waterClarity;
	// Water transparency along eye vector
	float waterVisibility; 

	// Range for the shore colouring area
	float shoreRange;
	// Horizontal extinction of the RGB channels, in world coordinates. 
	// Red wavelengths dissapear(get absorbed) at around 5m, followed by green(75m) and blue(300m).
	half3 horizontalExtinction;

	half3 shoreColor;
	half3 surfaceColor;
	half3 depthColor;
};

// waterTransparency - x = , y = water visibility along eye vector, 
// waterDepth = water depth in world space, viewWaterDepth = view/accumulated water depth in world space
half3 DepthRefraction( 
	depthRefractionParams props, float waterDepth, float viewWaterDepth,
	float3 refractionColor, out float depthExp)
{
	float accDepth = viewWaterDepth * props.waterClarity; // accumulated water depth
	float accDepthExp = saturate(accDepth / (2.5 * props.waterVisibility));
	accDepthExp *= (1.0 - accDepthExp) * accDepthExp * accDepthExp + 1; // out cubic

	half3 surfaceColor = lerp(props.shoreColor, props.surfaceColor, saturate(waterDepth / props.shoreRange));
	half3 waterColor = lerp(surfaceColor, props.depthColor, saturate(waterDepth / props.horizontalExtinction));
	half3 depthColor = props.depthColor;

	refractionColor = lerp(refractionColor, surfaceColor * waterColor, saturate(accDepth / props.waterVisibility));
	refractionColor = lerp(refractionColor, depthColor, accDepthExp);
	refractionColor = lerp(refractionColor, depthColor * waterColor, saturate(waterDepth / props.horizontalExtinction));

	float surfaceAlpha = lerp(0.5, 1.0, saturate(waterDepth / props.shoreRange));
	float waterAlpha = lerp(surfaceAlpha, 1.0, saturate(waterDepth / props.horizontalExtinction));

	depthExp = lerp(0, surfaceAlpha*waterAlpha, saturate(accDepth / props.waterVisibility));
	depthExp = lerp(depthExp, 1, accDepthExp);
	depthExp = lerp(depthExp, 0.1*waterAlpha, saturate(waterDepth / props.horizontalExtinction));
	return refractionColor;
}

// Refraction helpers. Based on Filament. 
struct Refraction {
    float3 position;
    float3 direction;
    float d;
};

void refractionSolidSphere(const float3 position, 
    const float etaIR, const float etaRI, const float thickness,
    const float3 n, float3 r, out Refraction ray) {
    r = refract(r, n, etaIR);
    float NoR = dot(n, r);
    float d = thickness * -NoR;
    ray.position = float3(position + r * d);
    ray.d = d;
    float3 n1 = normalize(NoR * r - n * 0.5);
    ray.direction = refract(r, n1, etaRI);
}

void refractionSolidBox(const float3 position, 
    const float etaIR, const float etaRI, const float thickness,
    const float3 n, float3 r, out Refraction ray) {
    float3 rr = refract(r, n, etaIR);
    float NoR = dot(n, rr);
    float d = thickness / max(-NoR, 0.001);
    ray.position = float3(position + rr * d);
    ray.direction = r;
    ray.d = d;
#if 0
    // fudge direction vector, so we see the offset due to the thickness of the object
    float envDistance = 10.0; // this should come from a ubo
    ray.direction = normalize((ray.position - position) + ray.direction * envDistance);
#endif
}

// Filament material helpers
float max3(const float3 v) {
    return max(v.x, max(v.y, v.z));
}

#define MIN_N_DOT_V 1e-4

float clampNoV(float NoV) {
    // Neubelt and Pettineo 2013, "Crafting a Next-gen Material Pipeline for The Order: 1886"
    return max(NoV, MIN_N_DOT_V);
}

float3 computeDiffuseColor(const float4 baseColor, float metallic) {
    return baseColor.rgb * (1.0 - metallic);
}

float3 computeF0(const float4 baseColor, float metallic, float reflectance) {
    return baseColor.rgb * metallic + (reflectance * (1.0 - metallic));
}

float computeDielectricF0(float reflectance) {
    return 0.16 * reflectance * reflectance;
}

float computeMetallicFromSpecularColor(const float3 specularColor) {
    return max3(specularColor);
}

float computeRoughnessFromGlossiness(float glossiness) {
    return 1.0 - glossiness;
}

float perceptualRoughnessToRoughness(float perceptualRoughness) {
    return perceptualRoughness * perceptualRoughness;
}

float roughnessToPerceptualRoughness(float roughness) {
    return sqrt(roughness);
}

float iorToF0(float transmittedIor, float incidentIor) {
    return sq((transmittedIor - incidentIor) / (transmittedIor + incidentIor));
}

float f0ToIor(float f0) {
    float r = sqrt(f0);
    return (1.0 + r) / (1.0 - r);
}

// Fog helpers

// MIT License
// Copyright © 2016 Inigo Quilez
float boxDensity( float3 wro, float3 wrd,   // ray origin, ray direction
                  float4x4 txx, float3 r,     // box center and orientation, box radius
                  float dbuffer )       // depth buffer
{
    float3 d = (mul(txx,float4(wrd,0.0))).xyz;
    float3 o = (mul(txx,float4(wro,1.0))).xyz;

	// ray-box intersection in box space
    float3 m = 1.0/d;
    float3 n = m*o;
    float3 k = abs(m)*r;
    float3 ta = -n - k;
    float3 tb = -n + k;
	float tN = max( max( ta.x, ta.y ), ta.z );
	float tF = min( min( tb.x, tb.y ), tb.z );
	if( tN > tF || tF < 0.0) return 0.0;

    // not visible (behind camera or behind dbuffer)
    if( tF<0.0 || tN>dbuffer ) return 0.0;

    // clip integration segment from camera to dbuffer
    tN = max( tN, 0.0 );
    tF = min( tF, dbuffer );
    
    // move ray to the intersection point
    o += tN*d; tF=tF-tN; tN=0.0;

    // density calculation. density is of the form
    //
    // d(x,y,z) = [1-(x/rx)^2] * [1-(y/ry)^2] * [1-(z/rz)^2];
    //
    // this can be analytically integrable (it's a degree 6 polynomial):
    
    float3 a = 1.0 -     (o*o)/(r*r);
    float3 b =     - 2.0*(o*d)/(r*r);
    float3 c =     -     (d*d)/(r*r);
    
    float t1 = tF;
    float t2 = t1*t1;
    float t3 = t2*t1;
    float t4 = t2*t2;
    float t5 = t2*t3;
    float t6 = t3*t3;
    float t7 = t3*t4;

    float f = (t1/1.0) *(a.x*a.y*a.z) + 
              (t2/2.0) *(a.x*a.y*b.z + a.x*b.y*a.z + b.x*a.y*a.z) + 
              (t3/3.0) *(a.x*a.y*c.z + a.x*b.y*b.z + a.x*c.y*a.z + b.x*a.y*b.z + b.x*b.y*a.z + c.x*a.y*a.z) +
              (t4/4.0) *(a.x*b.y*c.z + a.x*c.y*b.z + b.x*a.y*c.z + b.x*b.y*b.z + b.x*c.y*a.z + c.x*a.y*b.z + c.x*b.y*a.z) + 
              (t5/5.0) *(a.x*c.y*c.z + b.x*b.y*c.z + b.x*c.y*b.z + c.x*a.y*c.z + c.x*b.y*b.z + c.x*c.y*a.z) + 
              (t6/6.0) *(b.x*c.y*c.z + c.x*b.y*c.z + c.x*c.y*b.z) + 
              (t7/7.0) *(c.x*c.y*c.z);
      
    return f;
    
}

// Projected caustics helpers

float causticsEdgeFadeMask(float3 worldPosition, float radius, float offset)
{
    float3 objPos = mul(unity_WorldToObject, float4(worldPosition, 1.0)).xyz;
    float3 edgeFadeMaskXYZ = 1.0 - smoothstep(1.0 - radius, 1.0, abs(objPos) + offset);
    return edgeFadeMaskXYZ.x * edgeFadeMaskXYZ.y * edgeFadeMaskXYZ.z;
    
}

#endif // WATER_UTILS