#ifndef WATER_INDIRECT
#define WATER_INDIRECT

// Light probe/SH functions

// From https://github.com/lukis101/VRCUnityStuffs/tree/master/SH
// SH Convolution Functions
// Code adapted from https://blog.selfshadow.com/2012/01/07/righting-wrap-part-2/
///////////////////////////

float3 GeneralWrapSH(float fA) // original unoptimized
{
    // Normalization factor for our model.
    float norm = 0.5 * (2 + fA) / (1 + fA);
    float4 t = float4(2 * (fA + 1), fA + 2, fA + 3, fA + 4);
    return norm * float3(t.x / t.y, 2 * t.x / (t.y * t.z),
        t.x * (fA * fA - t.x + 5) / (t.y * t.z * t.w));
}
float3 GeneralWrapSHOpt(float fA)
{
    const float4 t0 = float4(-0.047771, -0.129310, 0.214438, 0.279310);
    const float4 t1 = float4( 1.000000,  0.666667, 0.250000, 0.000000);

    float3 r;
    r.xyz = saturate(t0.xxy * fA + t0.yzw);
    r.xyz = -r * fA + t1.xyz;
    return r;
}

float3 GreenWrapSHOpt(float fW)
{
    const float4 t0 = float4(0.0, 1.0 / 4.0, -1.0 / 3.0, -1.0 / 2.0);
    const float4 t1 = float4(1.0, 2.0 / 3.0,  1.0 / 4.0,  0.0);

    float3 r;
    r.xyz = t0.xxy * fW + t0.xzw;
    r.xyz = r.xyz * fW + t1.xyz;
    return r;
}

float3 ShadeSH9_wrapped(float3 normal, float3 conv)
{
    float3 x0, x1, x2;
    conv *= float3(1, 1.5, 4); // Undo pre-applied cosine convolution
    //conv *= _Bands.xyz; // debugging

    // Constant (L0)
    // Band 0 has constant part from 6th kernel (band 1) pre-applied, but ignore for performance
    x0 = float3(unity_SHAr.w, unity_SHAg.w, unity_SHAb.w);

    // Linear (L1) polynomial terms
    x1.r = (dot(unity_SHAr.xyz, normal));
    x1.g = (dot(unity_SHAg.xyz, normal));
    x1.b = (dot(unity_SHAb.xyz, normal));

    // 4 of the quadratic (L2) polynomials
    float4 vB = normal.xyzz * normal.yzzx;
    x2.r = dot(unity_SHBr, vB);
    x2.g = dot(unity_SHBg, vB);
    x2.b = dot(unity_SHBb, vB);

    // Final (5th) quadratic (L2) polynomial
    float vC = normal.x * normal.x - normal.y * normal.y;
    x2 += unity_SHC.rgb * vC;

    return x0 * conv.x + x1 * conv.y + x2 * conv.z;
}

float3 ShadeSH9_wrappedCorrect(float3 normal, float3 conv)
{
    const float3 cosconv_inv = float3(1, 1.5, 4); // Inverse of the pre-applied cosine convolution
    float3 x0, x1, x2;
    conv *= cosconv_inv; // Undo pre-applied cosine convolution
    //conv *= _Bands.xyz; // debugging

    // Constant (L0)
    x0 = float3(unity_SHAr.w, unity_SHAg.w, unity_SHAb.w);
    // Remove the constant part from L2 and add it back with correct convolution
    float3 otherband = float3(unity_SHBr.z, unity_SHBg.z, unity_SHBb.z) / 3.0;
    x0 = (x0 + otherband) * conv.x - otherband * conv.z;

    // Linear (L1) polynomial terms
    x1.r = (dot(unity_SHAr.xyz, normal));
    x1.g = (dot(unity_SHAg.xyz, normal));
    x1.b = (dot(unity_SHAb.xyz, normal));

    // 4 of the quadratic (L2) polynomials
    float4 vB = normal.xyzz * normal.yzzx;
    x2.r = dot(unity_SHBr, vB);
    x2.g = dot(unity_SHBg, vB);
    x2.b = dot(unity_SHBb, vB);

    // Final (5th) quadratic (L2) polynomial
    float vC = normal.x * normal.x - normal.y * normal.y;
    x2 += unity_SHC.rgb * vC;

    return x0 + x1 * conv.y + x2 * conv.z;
}

// 

#if UNITY_LIGHT_PROBE_PROXY_VOLUME
// normal should be normalized, w=1.0
half3 Irradiance_SampleProbeVolume (half4 normal, float3 worldPos)
{
    const float transformToLocal = unity_ProbeVolumeParams.y;
    const float texelSizeX = unity_ProbeVolumeParams.z;

    //The SH coefficients textures and probe occlusion are packed into 1 atlas.
    //-------------------------
    //| ShR | ShG | ShB | Occ |
    //-------------------------

    float3 position = (transformToLocal == 1.0f) ? mul(unity_ProbeVolumeWorldToObject, float4(worldPos, 1.0)).xyz : worldPos;
    float3 texCoord = (position - unity_ProbeVolumeMin.xyz) * unity_ProbeVolumeSizeInv.xyz;
    texCoord.x = texCoord.x * 0.25f;

    // We need to compute proper X coordinate to sample.
    // Clamp the coordinate otherwize we'll have leaking between RGB coefficients
    float texCoordX = clamp(texCoord.x, 0.5f * texelSizeX, 0.25f - 0.5f * texelSizeX);

    // sampler state comes from SHr (all SH textures share the same sampler)
    texCoord.x = texCoordX;
    half4 SHAr = UNITY_SAMPLE_TEX3D_SAMPLER(unity_ProbeVolumeSH, unity_ProbeVolumeSH, texCoord);

    texCoord.x = texCoordX + 0.25f;
    half4 SHAg = UNITY_SAMPLE_TEX3D_SAMPLER(unity_ProbeVolumeSH, unity_ProbeVolumeSH, texCoord);

    texCoord.x = texCoordX + 0.5f;
    half4 SHAb = UNITY_SAMPLE_TEX3D_SAMPLER(unity_ProbeVolumeSH, unity_ProbeVolumeSH, texCoord);

    // Linear + constant polynomial terms
    half3 x1;

        x1.r = dot(SHAr, normal);
        x1.g = dot(SHAg, normal);
        x1.b = dot(SHAb, normal);

    return x1;
}
#endif

float3 Irradiance_SphericalHarmonics(const float3 n, const bool useL2) {
    // Uses Unity's functions for reading SH. 
    // However, this function is currently unused. 
    float3 finalSH = float3(0,0,0); 
        #if (SPHERICAL_HARMONICS == SPHERICAL_HARMONICS_DEFAULT)
            finalSH = SHEvalLinearL0L1(half4(n, 1.0));
            if (useL2) finalSH += SHEvalLinearL2(half4(n, 1.0));
        #endif

        #if true
            float3 L0 = float3(unity_SHAr.w, unity_SHAg.w, unity_SHAb.w)
            + float3(unity_SHBr.z, unity_SHBg.z, unity_SHBb.z) / 3.0;
            finalSH.r = shEvaluateDiffuseL1Geomerics_local(L0.r, unity_SHAr.xyz, n);
            finalSH.g = shEvaluateDiffuseL1Geomerics_local(L0.g, unity_SHAg.xyz, n);
            finalSH.b = shEvaluateDiffuseL1Geomerics_local(L0.b, unity_SHAb.xyz, n);
        #endif

    return finalSH;
}

half3 Irradiance_SphericalHarmonicsUnity (half3 normal, float3 worldPos, float transmission = 1.0)
{
    half3 ambient_contrib = 0.0;
    float3 sh_conv = GeneralWrapSHOpt(transmission);

    #if UNITY_LIGHT_PROBE_PROXY_VOLUME
        if (unity_ProbeVolumeParams.x == 1.0)
            ambient_contrib = Irradiance_SampleProbeVolume(half4(normal, 1.0), worldPos);
        else
    		ambient_contrib += ShadeSH9_wrappedCorrect(normal, sh_conv);
    #else
        ambient_contrib = Irradiance_SphericalHarmonics(normal, true);
    	ambient_contrib += ShadeSH9_wrappedCorrect(normal, sh_conv);
    #endif

    ambient_contrib = max(half3(0, 0, 0), ambient_contrib);

    return ambient_contrib;
}

// Lightmap function

struct Light {
    float4 colorIntensity;  // rgb, pre-exposed intensity
    float3 l;
    float attenuation;
    float NoL;
};

Light ConvertToLight(UnityLight inLight)
{
    Light outLight = (Light)0;
    outLight.colorIntensity = float4(inLight.color, 1.0f);
    outLight.l = inLight.dir;
    return outLight;
}

UnityLight ConvertFromLight(Light outLight)
{
    UnityLight inLight = (UnityLight)0;
    inLight.color = outLight.colorIntensity;
    inLight.dir = outLight.l;
    return inLight;
}

float4 SampleShadowmaskBicubic(float2 uv)
{
    #ifdef SHADER_API_D3D11
        float width, height;
        unity_ShadowMask.GetDimensions(width, height);

        float4 unity_ShadowMask_TexelSize = float4(width, height, 1.0/width, 1.0/height);

        return SampleTexture2DBicubicFilter(TEXTURE2D_ARGS(unity_ShadowMask, samplerunity_ShadowMask),
            uv, unity_ShadowMask_TexelSize);
    #else
        return UNITY_SAMPLE_TEX2D_SAMPLER(unity_ShadowMask, unity_ShadowMask, uv);
    #endif
}

float4 SampleLightmapBicubic(float2 uv)
{
    #ifdef SHADER_API_D3D11
        float width, height;
        unity_Lightmap.GetDimensions(width, height);

        float4 unity_Lightmap_TexelSize = float4(width, height, 1.0/width, 1.0/height);

        return SampleTexture2DBicubicFilter(TEXTURE2D_ARGS(unity_Lightmap, samplerunity_Lightmap),
            uv, unity_Lightmap_TexelSize);
    #else
        return UNITY_SAMPLE_TEX2D_SAMPLER(unity_Lightmap, unity_Lightmap, uv);
    #endif
}

float4 SampleLightmapDirBicubic(float2 uv)
{
    #ifdef SHADER_API_D3D11
        float width, height;
        unity_LightmapInd.GetDimensions(width, height);

        float4 unity_LightmapInd_TexelSize = float4(width, height, 1.0/width, 1.0/height);

        return SampleTexture2DBicubicFilter(TEXTURE2D_ARGS(unity_LightmapInd, samplerunity_Lightmap),
            uv, unity_LightmapInd_TexelSize);
    #else
        return UNITY_SAMPLE_TEX2D_SAMPLER(unity_LightmapInd, unity_Lightmap, uv);
    #endif
}

float4 SampleDynamicLightmapBicubic(float2 uv)
{
    #ifdef SHADER_API_D3D11
        float width, height;
        unity_DynamicLightmap.GetDimensions(width, height);

        float4 unity_DynamicLightmap_TexelSize = float4(width, height, 1.0/width, 1.0/height);

        return SampleTexture2DBicubicFilter(TEXTURE2D_ARGS(unity_DynamicLightmap, samplerunity_DynamicLightmap),
            uv, unity_DynamicLightmap_TexelSize);
    #else
        return UNITY_SAMPLE_TEX2D_SAMPLER(unity_DynamicLightmap, unity_DynamicLightmap, uv);
    #endif
}

float4 SampleDynamicLightmapDirBicubic(float2 uv)
{
    #ifdef SHADER_API_D3D11
        float width, height;
        unity_DynamicDirectionality.GetDimensions(width, height);

        float4 unity_DynamicDirectionality_TexelSize = float4(width, height, 1.0/width, 1.0/height);

        return SampleTexture2DBicubicFilter(TEXTURE2D_ARGS(unity_DynamicDirectionality, samplerunity_DynamicLightmap),
            uv, unity_DynamicDirectionality_TexelSize);
    #else
        return UNITY_SAMPLE_TEX2D_SAMPLER(unity_DynamicDirectionality, unity_DynamicLightmap, uv);
    #endif
}


#if (defined(_BAKERY_RNM) || defined(_BAKERY_SH))
#define USING_BAKERY
#if defined(SHADER_API_D3D11)
TEXTURE2D_HALF(_RNM0);
TEXTURE2D_HALF(_RNM1);
TEXTURE2D_HALF(_RNM2);
#else
sampler2D _RNM0;
sampler2D _RNM1;
sampler2D _RNM2;
#endif
#endif


#if defined(USING_BAKERY) && defined(LIGHTMAP_ON)
// needs specular variant?
float3 DecodeRNMLightmap(half3 color, half2 lightmapUV, half3 normalTangent, float3x3 tangentToWorld, out Light o_light)
{
    const float rnmBasis0 = float3(0.816496580927726f, 0, 0.5773502691896258f);
    const float rnmBasis1 = float3(-0.4082482904638631f, 0.7071067811865475f, 0.5773502691896258f);
    const float rnmBasis2 = float3(-0.4082482904638631f, -0.7071067811865475f, 0.5773502691896258f);

    float3 irradiance;
    o_light = (Light)0;

    #ifdef SHADER_API_D3D11
        float width, height;
        _RNM0.GetDimensions(width, height);

        float4 rnm_TexelSize = float4(width, height, 1.0/width, 1.0/height);
        
        float3 rnm0 = DecodeLightmap(SampleTexture2DBicubicFilter(TEXTURE2D_ARGS(_RNM0, sampler_RNM0), lightmapUV, rnm_TexelSize));
        float3 rnm1 = DecodeLightmap(SampleTexture2DBicubicFilter(TEXTURE2D_ARGS(_RNM1, sampler_RNM0), lightmapUV, rnm_TexelSize));
        float3 rnm2 = DecodeLightmap(SampleTexture2DBicubicFilter(TEXTURE2D_ARGS(_RNM2, sampler_RNM0), lightmapUV, rnm_TexelSize));
    #else
        float3 rnm0 = DecodeLightmap(UNITY_SAMPLE_TEX2D_SAMPLER(_RNM0, _RNM0, lightmapUV));
        float3 rnm1 = DecodeLightmap(UNITY_SAMPLE_TEX2D_SAMPLER(_RNM1, _RNM0, lightmapUV));
        float3 rnm2 = DecodeLightmap(UNITY_SAMPLE_TEX2D_SAMPLER(_RNM2, _RNM0, lightmapUV));
    #endif

    normalTangent.g *= -1;

    irradiance =  saturate(dot(rnmBasis0, normalTangent)) * rnm0
                + saturate(dot(rnmBasis1, normalTangent)) * rnm1
                + saturate(dot(rnmBasis2, normalTangent)) * rnm2;

    #if defined(_LIGHTMAPSPECULAR)
    float3 dominantDirT = rnmBasis0 * luminance(rnm0) +
                          rnmBasis1 * luminance(rnm1) +
                          rnmBasis2 * luminance(rnm2);

    float3 dominantDirTN = normalize(dominantDirT);
    float3 specColor = saturate(dot(rnmBasis0, dominantDirTN)) * rnm0 +
                       saturate(dot(rnmBasis1, dominantDirTN)) * rnm1 +
                       saturate(dot(rnmBasis2, dominantDirTN)) * rnm2;                        

    o_light.l = normalize(mul(tangentToWorld, dominantDirT));
    half directionality = max(0.001, length(o_light.l));
    o_light.l /= directionality;

    // Split light into the directional and ambient parts, according to the directionality factor.
    o_light.colorIntensity = float4(specColor * directionality, 1.0);
    o_light.attenuation = directionality;
    o_light.NoL = saturate(dot(normalTangent, dominantDirTN));
    #endif

    return irradiance;
}

float3 DecodeSHLightmap(half3 L0, half2 lightmapUV, half3 normalWorld, out Light o_light)
{
    float3 irradiance;
    o_light = (Light)0;

    #ifdef SHADER_API_D3D11
        float width, height;
        _RNM0.GetDimensions(width, height);

        float4 rnm_TexelSize = float4(width, height, 1.0/width, 1.0/height);
        
        float3 nL1x = SampleTexture2DBicubicFilter(TEXTURE2D_ARGS(_RNM0, sampler_RNM0), lightmapUV, rnm_TexelSize);
        float3 nL1y = SampleTexture2DBicubicFilter(TEXTURE2D_ARGS(_RNM1, sampler_RNM0), lightmapUV, rnm_TexelSize);
        float3 nL1z = SampleTexture2DBicubicFilter(TEXTURE2D_ARGS(_RNM2, sampler_RNM0), lightmapUV, rnm_TexelSize);
    #else
        float3 nL1x = UNITY_SAMPLE_TEX2D_SAMPLER(_RNM0, _RNM0, lightmapUV);
        float3 nL1y = UNITY_SAMPLE_TEX2D_SAMPLER(_RNM1, _RNM0, lightmapUV);
        float3 nL1z = UNITY_SAMPLE_TEX2D_SAMPLER(_RNM2, _RNM0, lightmapUV);
    #endif

    nL1x = nL1x * 2 - 1;
    nL1y = nL1y * 2 - 1;
    nL1z = nL1z * 2 - 1;
    float3 L1x = nL1x * L0 * 2;
    float3 L1y = nL1y * L0 * 2;
    float3 L1z = nL1z * L0 * 2;

    #ifdef BAKERY_SHNONLINEAR
        float lumaL0 = dot(L0, float(1));
        float lumaL1x = dot(L1x, float(1));
        float lumaL1y = dot(L1y, float(1));
        float lumaL1z = dot(L1z, float(1));
        float lumaSH = shEvaluateDiffuseL1Geomerics_local(lumaL0, float3(lumaL1x, lumaL1y, lumaL1z), normalWorld);

        irradiance = L0 + normalWorld.x * L1x + normalWorld.y * L1y + normalWorld.z * L1z;
        float regularLumaSH = dot(irradiance, 1);
        irradiance *= lerp(1, lumaSH / regularLumaSH, saturate(regularLumaSH*16));
    #else
        irradiance = L0 + normalWorld.x * L1x + normalWorld.y * L1y + normalWorld.z * L1z;
    #endif

    #if defined(_LIGHTMAPSPECULAR)
    float3 dominantDir = float3(luminance(nL1x), luminance(nL1y), luminance(nL1z));

    o_light.l = dominantDir;
    half directionality = max(0.001, length(o_light.l));
    o_light.l /= directionality;

    // Split light into the directional and ambient parts, according to the directionality factor.
    o_light.colorIntensity = float4(irradiance * directionality, 1.0);
    o_light.attenuation = directionality;
    o_light.NoL = saturate(dot(normalWorld, o_light.l));
    #endif

    return irradiance;
}
#endif

#if defined(_BAKERY_MONOSH)
float3 DecodeMonoSHLightmap(half3 L0, half2 lightmapUV, half3 normalWorld, out Light o_light)
{
    o_light = (Light)0;

    float3 dominantDir = SampleLightmapDirBicubic (lightmapUV);

    float3 nL1 = dominantDir * 2 - 1;
    float3 L1x = nL1.x * L0 * 2;
    float3 L1y = nL1.y * L0 * 2;
    float3 L1z = nL1.z * L0 * 2;

    float3 sh;

#if BAKERY_SHNONLINEAR
    float lumaL0 = dot(L0, 1);
    float lumaL1x = dot(L1x, 1);
    float lumaL1y = dot(L1y, 1);
    float lumaL1z = dot(L1z, 1);
    float lumaSH = shEvaluateDiffuseL1Geomerics_local(lumaL0, float3(lumaL1x, lumaL1y, lumaL1z), normalWorld);

    sh = L0 + normalWorld.x * L1x + normalWorld.y * L1y + normalWorld.z * L1z;
    float regularLumaSH = dot(sh, 1);

    sh *= lerp(1, lumaSH / regularLumaSH, saturate(regularLumaSH*16));
#else
    sh = L0 + normalWorld.x * L1x + normalWorld.y * L1y + normalWorld.z * L1z;
#endif

    #if defined(_LIGHTMAPSPECULAR)
    dominantDir = nL1;

    o_light.l = dominantDir;
    half directionality = max(0.001, length(o_light.l));
    o_light.l /= directionality;

    // Split light into the directional and ambient parts, according to the directionality factor.
    o_light.colorIntensity = float4(L0 * directionality, 1.0);
    o_light.attenuation = directionality;
    o_light.NoL = saturate(dot(normalWorld, o_light.l));
    #endif

    return sh;
}
#endif

float IrradianceToExposureOcclusion(float3 irradiance, float occlusionPow)
{
    return saturate(length(irradiance + FLT_EPS) * occlusionPow);
}

// Workaround for Unity bug with lightmap sampler not being defined
// https://issuetracker.unity3d.com/issues/shader-cannot-find-frag-surf-and-vert-surf-and-throws-errors-in-the-console-and-inspector
fixed UnitySampleBakedOcclusion_local (float2 lightmapUV, float3 worldPos)
{
    #if defined (SHADOWS_SHADOWMASK)
        #if defined(LIGHTMAP_ON)
            fixed4 rawOcclusionMask = SampleShadowmaskBicubic(lightmapUV.xy);
        #else
            fixed4 rawOcclusionMask = fixed4(1.0, 1.0, 1.0, 1.0);
            #if UNITY_LIGHT_PROBE_PROXY_VOLUME
                if (unity_ProbeVolumeParams.x == 1.0)
                    rawOcclusionMask = LPPV_SampleProbeOcclusion(worldPos);
                else
                    rawOcclusionMask = SampleShadowmaskBicubic(lightmapUV.xy);
            #else
                rawOcclusionMask = SampleShadowmaskBicubic(lightmapUV.xy);
            #endif
        #endif
        return saturate(dot(rawOcclusionMask, unity_OcclusionMaskSelector));

    #else

        //In forward dynamic objects can only get baked occlusion from LPPV, light probe occlusion is done on the CPU by attenuating the light color.
        fixed atten = 1.0f;
        #if defined(UNITY_INSTANCING_ENABLED) && defined(UNITY_USE_SHCOEFFS_ARRAYS)
            // ...unless we are doing instancing, and the attenuation is packed into SHC array's .w component.
            atten = unity_SHC.w;
        #endif

        #if UNITY_LIGHT_PROBE_PROXY_VOLUME && !defined(LIGHTMAP_ON) && !UNITY_STANDARD_SIMPLE
            fixed4 rawOcclusionMask = atten.xxxx;
            if (unity_ProbeVolumeParams.x == 1.0)
                rawOcclusionMask = LPPV_SampleProbeOcclusion(worldPos);
            return saturate(dot(rawOcclusionMask, unity_OcclusionMaskSelector));
        #endif

        return atten;
    #endif
}
// Occlusion is applied in the shader; output baked attenuation for SSS instead
inline UnityGI UnityGI_Base_local(UnityGIInput data, out half bakedAtten, inout half occlusion, 
	half3 normalWorld, float perceptualRoughness, half3 transmission, float exposureOcclusion, float probeTransmission,
    SSSParams sssData)
{
    UnityGI o_gi;
    ResetUnityGI(o_gi);

    o_gi.indirect.diffuse = data.ambient;

    float3 irradianceForAO = 1.0;

    // Base pass with Lightmap support is responsible for handling ShadowMask / blending here for performance reason
    bakedAtten = 1.0;

    #if defined(HANDLE_SHADOWS_BLENDING_IN_GI)
        bakedAtten = UnitySampleBakedOcclusion_local(data.lightmapUV.xy, data.worldPos);
        float zDist = dot(_WorldSpaceCameraPos - data.worldPos, UNITY_MATRIX_V[2].xyz);
        float fadeDist = UnityComputeShadowFadeDistance(data.worldPos, zDist);
        data.atten = UnityMixRealtimeAndBakedShadows(data.atten, bakedAtten, UnityComputeShadowFade(fadeDist));
    #endif

    o_gi.light = data.light;
    o_gi.light.color *= data.atten;

	Light filamentLight = (Light)0;

    #if UNITY_SHOULD_SAMPLE_SH
//        o_gi.indirect.diffuse = ShadeSHPerPixel(normalWorld, data.ambient, data.worldPos);
    	o_gi.indirect.diffuse = Irradiance_SphericalHarmonicsUnity(normalWorld, data.worldPos, probeTransmission);
    #endif

    #if defined(LIGHTMAP_ON)
        // Baked lightmaps
        half4 bakedColorTex = SampleLightmapBicubic (data.lightmapUV.xy);
        half3 bakedColor = DecodeLightmap(bakedColorTex);

        #ifdef DIRLIGHTMAP_COMBINED
            fixed4 bakedDirTex = UNITY_SAMPLE_TEX2D_SAMPLER (unity_LightmapInd, unity_Lightmap, data.lightmapUV.xy);

            // Bakery's MonoSH mode replaces the regular directional lightmap
            #if defined(_BAKERY_MONOSH)
                o_gi.indirect.diffuse += DecodeMonoSHLightmap (bakedColor, data.lightmapUV.xy, normalWorld, filamentLight);
                irradianceForAO = o_gi.indirect.diffuse;

                #if defined(LIGHTMAP_SHADOW_MIXING) && !defined(SHADOWS_SHADOWMASK) && defined(SHADOWS_SCREEN)
                    o_gi.indirect.diffuse = SubtractMainLightWithRealtimeAttenuationFromLightmap (o_gi.indirect.diffuse, bakedAtten, bakedColorTex, normalWorld);
                #endif
            #else

				o_gi.indirect.diffuse += DecodeDirectionalLightmap (bakedColor, bakedDirTex, normalWorld);
				irradianceForAO = o_gi.indirect.diffuse;

				#if defined(LIGHTMAP_SHADOW_MIXING) && !defined(SHADOWS_SHADOWMASK) && defined(SHADOWS_SCREEN)
					ResetUnityLight(o_gi.light);
					o_gi.indirect.diffuse = SubtractMainLightWithRealtimeAttenuationFromLightmap (o_gi.indirect.diffuse, data.atten, bakedColorTex, normalWorld);
				#endif
            #endif

        #else // not directional lightmap

            #if defined(USING_BAKERY)
                #if defined(_BAKERY_RNM)
                // bakery rnm mode
                o_gi.indirect.diffuse = DecodeRNMLightmap(bakedColor, data.lightmapUV.xy, tangentNormal, shading.tangentToWorld, filamentLight);
                #endif

                #if defined(_BAKERY_SH)
                // bakery sh mode
                o_gi.indirect.diffuse = DecodeSHLightmap(bakedColor, data.lightmapUV.xy, normalWorld, filamentLight);
                #endif

                irradianceForAO = o_gi.indirect.diffuse;

                #if defined(LIGHTMAP_SHADOW_MIXING) && !defined(SHADOWS_SHADOWMASK) && defined(SHADOWS_SCREEN)
                    o_gi.indirect.diffuse = SubtractMainLightWithRealtimeAttenuationFromLightmap(o_gi.indirect.diffuse, bakedAtten, bakedColorTex, normalWorld);
                #endif

            #else
           		o_gi.indirect.diffuse += bakedColor;

                irradianceForAO = o_gi.indirect.diffuse;

				#if defined(LIGHTMAP_SHADOW_MIXING) && !defined(SHADOWS_SHADOWMASK) && defined(SHADOWS_SCREEN)
					ResetUnityLight(o_gi.light);
					o_gi.indirect.diffuse = SubtractMainLightWithRealtimeAttenuationFromLightmap(o_gi.indirect.diffuse, data.atten, bakedColorTex, normalWorld);
				#endif
			#endif
        #endif
    #endif

    #ifdef DYNAMICLIGHTMAP_ON
        // Dynamic lightmaps
        fixed4 realtimeColorTex = SampleDynamicLightmapBicubic(data.lightmapUV.zw);
        half3 realtimeColor = DecodeRealtimeLightmap (realtimeColorTex);
		irradianceForAO += realtimeColor;

        #ifdef DIRLIGHTMAP_COMBINED
            half4 realtimeDirTex = UNITY_SAMPLE_TEX2D_SAMPLER(unity_DynamicDirectionality, unity_DynamicLightmap, data.lightmapUV.zw);
            o_gi.indirect.diffuse += DecodeDirectionalLightmap (realtimeColor, realtimeDirTex, normalWorld);
        #else
            o_gi.indirect.diffuse += realtimeColor;
        #endif
    #endif
    
	occlusion *= IrradianceToExposureOcclusion(irradianceForAO, 1.0/exposureOcclusion);

	// o_gi.light stores the data for the main light, so a seperate light must be output for specular
	// or else it must be calculated here.

    float focus = saturate(length(filamentLight.l));
    half3 halfDir = Unity_SafeNormalize(normalize(filamentLight.l) - data.worldViewDir);
    half nh = saturate(dot(normalWorld, halfDir));
    half roughness = PerceptualRoughnessToRoughness(perceptualRoughness);
    half spec = GGXTerm(nh, roughness);

    float sh = filamentLight.NoL * filamentLight.colorIntensity;

    o_gi.indirect.specular += max(spec * sh, 0.0);

	// Apply subsurface and add to indirect.diffuse
	float3 sssLighting = getSubsurfaceScatteringLight(sssData, filamentLight.l, 
	normalWorld, // should correct for backfaces
	data.worldViewDir, transmission) * filamentLight.colorIntensity;
	o_gi.indirect.diffuse += sssLighting;

    //o_gi.indirect.diffuse *= occlusion;
    return o_gi;
}

// Reflection Probes

UnityGIInput InitialiseUnityGIInput(float3 worldPos, float3 worldViewDir)
{
    UnityGIInput d;
    d.worldPos = worldPos;
    d.worldViewDir = -worldViewDir;
    d.probeHDR[0] = unity_SpecCube0_HDR;
    d.probeHDR[1] = unity_SpecCube1_HDR;
    #if defined(UNITY_SPECCUBE_BLENDING) || defined(UNITY_SPECCUBE_BOX_PROJECTION)
      d.boxMin[0] = unity_SpecCube0_BoxMin; // .w holds lerp value for blending
    #endif
    #ifdef UNITY_SPECCUBE_BOX_PROJECTION
      d.boxMax[0] = unity_SpecCube0_BoxMax;
      d.probePosition[0] = unity_SpecCube0_ProbePosition;
      d.boxMax[1] = unity_SpecCube1_BoxMax;
      d.boxMin[1] = unity_SpecCube1_BoxMin;
      d.probePosition[1] = unity_SpecCube1_ProbePosition;
    #endif
    return d;
}

half3 Unity_GlossyEnvironment_local (UNITY_ARGS_TEXCUBE(tex), half4 hdr, Unity_GlossyEnvironmentData glossIn)
{
    half perceptualRoughness = glossIn.roughness /* perceptualRoughness */ ;

    // Unity derivation
    perceptualRoughness = perceptualRoughness*(1.7 - 0.7 * perceptualRoughness);
    
    half mip = perceptualRoughnessToMipmapLevel(perceptualRoughness);
    half3 R = glossIn.reflUVW;
    half4 rgbm = UNITY_SAMPLE_TEXCUBE_LOD(tex, R, mip);

    return DecodeHDR(rgbm, hdr);
}

inline half3 UnityGI_prefilteredRadiance(const UnityGIInput data, const float perceptualRoughness, const float3 r)
{
    half3 specular;

    Unity_GlossyEnvironmentData glossIn = (Unity_GlossyEnvironmentData)0;
    glossIn.roughness = perceptualRoughness;
    glossIn.reflUVW = r;

    #ifdef UNITY_SPECCUBE_BOX_PROJECTION
        // we will tweak reflUVW in glossIn directly (as we pass it to Unity_GlossyEnvironment twice for probe0 and probe1), so keep original to pass into BoxProjectedCubemapDirection
        half3 originalReflUVW = glossIn.reflUVW;
        glossIn.reflUVW = BoxProjectedCubemapDirection (originalReflUVW, data.worldPos, data.probePosition[0], data.boxMin[0], data.boxMax[0]);
    #endif

    #ifdef _GLOSSYREFLECTIONS_OFF
        specular = unity_IndirectSpecColor.rgb;
    #else
        half3 env0 = Unity_GlossyEnvironment_local (UNITY_PASS_TEXCUBE(unity_SpecCube0), data.probeHDR[0], glossIn);
        #ifdef UNITY_SPECCUBE_BLENDING
            const float kBlendFactor = 0.99999;
            float blendLerp = data.boxMin[0].w;
            UNITY_BRANCH
            if (blendLerp < kBlendFactor)
            {
                #ifdef UNITY_SPECCUBE_BOX_PROJECTION
                    glossIn.reflUVW = BoxProjectedCubemapDirection (originalReflUVW, data.worldPos, data.probePosition[1], data.boxMin[1], data.boxMax[1]);
                #endif

                half3 env1 = Unity_GlossyEnvironment_local (UNITY_PASS_TEXCUBE_SAMPLER(unity_SpecCube1,unity_SpecCube0), data.probeHDR[1], glossIn);
                specular = lerp(env1, env0, blendLerp);
            }
            else
            {
                specular = env0;
            }
        #else
            specular = env0;
        #endif
    #endif

    return specular;
}

#endif // WATER_INDIRECT