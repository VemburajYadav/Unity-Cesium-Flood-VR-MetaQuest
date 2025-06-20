//-----------------------------------------------------------------------------------
// SCREEN SPACE REFLECTIONS
// Original shader by error.mdl, Toocanz, and Xiexe. 
// This version backports many of the improvements made by error.mdl in the SLZ
// Custom RP. Please see https://github.com/StressLevelZero/Custom-URP for details and license.
//-----------------------------------------------------------------------------------

#ifndef WATER_SSR
#define WATER_SSR

struct SSRData
{
	float3	wPos;
	float3	viewDir;
	float3	rayDir;
	half3	faceNormal;
	half	perceptualRoughness;
	half	RdotV;
	float4 noise;
};


SSRData GetSSRData(
	float3	wPos,
	float3	viewDir,
	half3	rayDir,
	half3	faceNormal,
	half	perceptualRoughness,
	half	RdotV,
	half4   noise)
{
	SSRData ssrData;
	ssrData.wPos = wPos;
	ssrData.viewDir = viewDir;
	ssrData.rayDir = normalize(rayDir);
	ssrData.faceNormal = normalize(faceNormal);
	ssrData.perceptualRoughness = perceptualRoughness;
	ssrData.RdotV = RdotV;
	ssrData.noise = noise;
	return ssrData;
}

/** @brief Scales SSR step size based on distance and angle such that a step moves the ray by about one pixel in 2D screenspace
 *
 *	@param rayDir Direction of the ray
 *  @param rayPos Camera space position of the ray
 *
 *  @return Step size scaled to move the ray by one pixel
 */
float perspectiveScaledStep(const float3 rayDir, float3 rayPos)
{
	// Vector between rayDir and a ray from the camera to the ray's position scaled to have the same z value as raydir.
	// This is approximately the xy-distance in perspective distorted space the ray will move with a step size of 1
	float2 screenRay = mad((-rayDir.z / rayPos.z), rayPos.xy, rayDir.xy);
	float invScreenLen = rsqrt(mad(screenRay.x, screenRay.x, (screenRay.y * screenRay.y)));
	// Create scaling factor, which when multiplied by the ray's Z position will give a step size that will move the ray by about 1 pixel in the X,Y plane of the screen
	// _SSRDistScale is tan(half FOV) / (half screen vertical resolution)
        // Extract the vertical FOV from the projection matrix
        float halfFov = atan(1.0 / UNITY_MATRIX_P[1][1]);

        // Get the vertical resolution from _ScreenParams
        float halfVerticalResolution = _ScreenParams.y * 0.5;

        // Calculate the final value
        float SSRDistScale = tan(halfFov) / halfVerticalResolution;
	float distScale = min(SSRDistScale * invScreenLen, 1.0e12);

	return distScale * abs(rayPos.z);
}

/** @brief Partially transforms a given camera space point to screenspace in 7 operations for the purposes of computing its screen UV position
 *
 *  Normally, transforming from camera space to projection space involves multiplying a 4x4 matrix
 *  by a float4 for a total of 28 operations. However, most of the elements of the camera to projection
 *  matrix are 0's, we don't need the z component for getting screen coordinates, and the w component is
 *  is just the negative of the input's z. Just doing the necessary calculations reduces the operations down to just 7.
 *	NOTE: this assumes an orthogonal projection matrix, might not work for some headsets (pimax) with non-parallel near/far
 *  planes
 *
 *  @param pos camera space coordinate to transform
 *  @return float3 containing the x and y projection space coordinates, and the z component for perspective correction
 */

float3 CameraToScreenPosCheap(const float3 pos)
{
	return float3(
        pos.x * UNITY_MATRIX_P._m00 + pos.z * UNITY_MATRIX_P._m02, 
        pos.y * UNITY_MATRIX_P._m11 + pos.z * UNITY_MATRIX_P._m12, 
        -pos.z);
}

/** @brief Computes the tangent of the half-angle of the cone that encompasses the
 *  Phong specular lobe. Used for determining the range of random ray directions and
 *  the mip level from the color pyramid to sample. Formula is derived from 
 *  Lawrence 2002 "Importance Sampling of the Phong Reflectance Mode". Lawrence
 *  gives the angle between perfect specular and random ray as arccos(u^(1/(n+1))
 *  where u is a random value and n is the phong power. Uludag 2014 "Hi-Z 
 *  Screen-Space Cone-Traced Re?ections" sets u to a constant of 0.244 to 
 *  get the average angle. Karis 2013 "Specular BRDF Reference" converts the
 *  phong specular exponent to physical roughness as n = 2/r^2 - 2. Combining
 *  this with the formula for the angle, the angle is almost a linear function
 *  of roughness on the 0-1 range, where theta ~= 1.33 r. We want the tangent
 *  of the angle for our use case, and using the approximation 
 *  tan(x) ~= 1/(1-(2/pi)*x) - 1 plus some tweaking of constants to get a better
 *  fit we get our formula tan(theta) = 1/(1 - (2.5 / pi) * r^2) - 1.0;
 * 
 */
float TanPhongConeAngle(const float roughness)
{
	float roughness2 = roughness;
	float alpha = roughness2 / (2 - roughness2);
	return rcp(1 - (2.5 * UNITY_INV_PI) * alpha) - 1.0;
}

/* 
 * BiRP's old screeen position calcuation, modified slightly to only output a float3 instead of a 
 * float4 since the z-component is worthless, putting the w in the z instead
 * 
 * @param pos projection-space position to calculate the screen uv's of
 * @return float3 containing the screen uvs (xy) and the perspective factor (z)
 */
inline float3 SSR_ComputeGrabScreenPos(float3 pos) 
{
#if UNITY_UV_STARTS_AT_TOP
	float scale = -1.0;
#else
	float scale = 1.0;
#endif
	float3 o = pos * 0.5f;
	o.xy = float2(o.x, o.y * scale) + o.z;
#ifdef UNITY_SINGLE_PASS_STEREO
    o.xy = TransformStereoScreenSpaceTex(o.xy, pos.z);
#endif
	o.z = pos.z;
	return o;
}


/** @brief March a ray from a given position in a given direction
 *         until it intersects the depth buffer.
 *
 *  Given a starting location and direction, march a ray in steps scaled
 *  to the pixel size at the ray's current
 *  position. At each step convert the ray's position to screenspace
 *  coordinates and depth, and compare to the depth texture's value at that location.
 *  If the depth difference at the ray's current position is >2x the step size,
 *  double the ray's step size to match. Otherwise, half the step size.
 *  If the depth from the depth buffer is also smaller
 *  than the ray's current depth, also reverse the direction. Repeat until the ray
 *  is within hitRadius of the depth texture or the maximum number of
 *  iterations is exceeded. Additionally, the loop will be cut short if the
 *  ray passes out of the camera's view.
 *  
 *  @param reflectedRay Starting position of the ray, in camera space
 *  @param rayDir Direction the ray is going, in camera space
 *  @param hitRadius Distance above/below the depth texture the ray must be
 *         before it can be considered to have successfully intersected the
 *         depth texture, as a fraction of the step size.
 *  @param noise Random noise added to modify the hit radius. This helps to
 *		   hide stair-step artifacts from the ray-marching process.
 *  @return The final xyz position of the ray, with the number of iterations
 *          it took stored in the w component. If the function ran out of
 *          iterations or the ray went off screen, the xyz will be (0,0,0).
 */
float4 SSR_reflect_ray(float3 reflectedRay, float3 rayDir,
    float hitRadius, float noise, half FdotR, const int maxIterations)
{    
	bool movingForwards = true;
	float3 finalPos = float3(1.#INF,0,0);
	
	float stepMultiplier = 1.0f;

	float dynStepSize = perspectiveScaledStep(rayDir.xyz, reflectedRay.xyz);
	hitRadius = mad(noise, hitRadius, hitRadius);
	float dynHitRadius = hitRadius * dynStepSize;
	float largeRadius = max(2 * dynStepSize * stepMultiplier, hitRadius);
	
	float totalDistance = 0.0f;
	float FdotR4 = FdotR * FdotR;
	FdotR4 *= FdotR4;
	reflectedRay += lerp(0, 0.5*largeRadius, 1 - FdotR4) * rayDir;
	bool storeLastPos = true;
	for (int i = 0; i < maxIterations; i++)
	{
		float3 spos = SSR_ComputeGrabScreenPos(CameraToScreenPosCheap(reflectedRay));

		float2 uvDepth = spos.xy / spos.z;

		//If the ray is outside of the eye's portion of the screen, we can stop there's no relevant information here
		if (any(uvDepth.xy > 1) || any(uvDepth.xy < 0))
		{
			break;
		}

		float rawDepth = screenDepthClamped(uvDepth);// tex2Dlod(_CameraDepthTexture,float4(uvDepth,0,0));
		float linearDepth = Linear01Depth(rawDepth);
		if (linearDepth == 0)
		{
			break;
		}

		linearDepth = linearDepth >= 0.999999 ? 1.#INF : linearDepth;
		//float sampleDepth = -mul(worldToDepth, float4(reflectedRay.xyz, 1)).z;
		float sampleDepth = -reflectedRay.z;
		float realDepth = linearDepth * _ProjectionParams.z;

		float depthDifference = abs(sampleDepth - realDepth);

		if (depthDifference > 2 * largeRadius)
		{
				stepMultiplier += stepMultiplier;
				largeRadius += largeRadius;
		}
        
		bool inLargeRadius = depthDifference < largeRadius;
		bool inHitRadius = depthDifference < dynHitRadius;
		bool isRayInFront = sampleDepth < realDepth;

		// Save first position the ray went behind an object as the final position
		// If the ray never hits, this position will be used instead of falling back
		// to the cubemap. This fills holes behind objects less obviously than sampling
		// from the cubemap
		if (!isRayInFront && storeLastPos)
		{
			finalPos = reflectedRay;
		}
		storeLastPos = isRayInFront ? true : false;
		// If we're within the hit radius, we're done
		UNITY_BRANCH if (inHitRadius)
		{
			finalPos = reflectedRay;
			totalDistance = -totalDistance;
			break;
		}

		// Swap directions if the ray is moving away from the depth surface, and if the step size is small enough
		// to avoid issues with the ray never resolving
		if (movingForwards)
		{
			if (inLargeRadius && !isRayInFront)
			{
				movingForwards = false;
				stepMultiplier = 0.5 * stepMultiplier;
			}
		}
		else
		{
			if (isRayInFront)
			{
				movingForwards = true;
				stepMultiplier = 0.5 * stepMultiplier;
			}
		}

		// Move forward a step if the ray is above depth or if it is more than 2 steps behind the depth
		// or if the step size is small enough. Don't move otherwise to prevent moving backwards towards a false
		// surface created by a high level mip
		if (isRayInFront || !inLargeRadius)
		{
			float step = movingForwards ? dynStepSize * stepMultiplier : -dynStepSize * stepMultiplier;
			reflectedRay = mad(rayDir, step, reflectedRay);
			totalDistance += step;

			dynStepSize = max(perspectiveScaledStep(rayDir.xyz, reflectedRay.xyz), hitRadius);
			dynHitRadius = hitRadius * dynStepSize;

			largeRadius = max(2.0 * dynStepSize * stepMultiplier, hitRadius);
		}
	}
	return float4(finalPos.xyz, totalDistance);
}

float4 SSR_GetRayDir(float4 wPos, half4 wNormal)
{
	// Trace a vector from the camera to the world-space location of the pixel being rendered.
	float3 viewDir = normalize(wPos.xyz - _WorldSpaceCameraPos);
	
	//Calculate the direction of the reflected ray off the surface
	float4 rayDir = float4(reflect(viewDir, wNormal).xyz,0);

	return rayDir;
}

/** @brief Gets the reflected color for a pixel
 *
 *  @param data Struct containing all necessary data for the SSR marcher
 *  @return Color of the screenspace reflection. The alpha component contains a fade factor to be used for blending with normal cubemap reflections
 *			for when the ray fails to hit anything or the ray goes offscreen
 */

float4 getSSRColor(SSRData data)
{
	float FdotR = dot(data.faceNormal, data.rayDir.xyz);
	
	UNITY_BRANCH if (FdotR <= 0)
	{
		return float4(0, 0, 0, 0);
	}

	float3 screenUVs = SSR_ComputeGrabScreenPos(mul(UNITY_MATRIX_VP, float4(data.wPos,1)).xyw);
	screenUVs.xy = screenUVs.xy / screenUVs.z;

	// Ray's starting position, in camera space
	float3 reflectedRay = mul(UNITY_MATRIX_V, float4(data.wPos.xyz, 1)).xyz;

	// Random offset to the ray, based on roughness
	float rayTanAngle = TanPhongConeAngle(data.perceptualRoughness * data.perceptualRoughness); 
	float3 rayNoise = rayTanAngle * (2*data.noise.rgb - 1);
	rayNoise = rayNoise - dot(rayNoise, data.faceNormal) * data.faceNormal; 
	data.rayDir += rayNoise;
	data.rayDir.xyz = normalize(data.rayDir.xyz);

	float RdotV = saturate(0.95 * dot(data.rayDir, -data.viewDir.xyz) + 0.05);

	UNITY_BRANCH if (RdotV <= 0)
	{
		return float4(0, 0, 0, 0);
	}

	data.rayDir = mul(UNITY_MATRIX_V, float4(data.rayDir.xyz, 0));
	
	float3 screenOffset = normalize(mul(UNITY_MATRIX_V, float4(data.faceNormal, 0)));
	
	reflectedRay += 2.0 * screenOffset * perspectiveScaledStep(float3(screenOffset), reflectedRay);
    
    float SSRHitRadius = 0.05;
    const int SSR_STEP_COUNT = 16;
	
	float4 finalPos = SSR_reflect_ray(reflectedRay, data.rayDir, SSRHitRadius, data.noise.r, FdotR, SSR_STEP_COUNT);
	
	float totalDistance = finalPos.w;
	finalPos.w = 1;

	if (finalPos.x == 1.#INF) 
	{
		return float4(0,0,0,0);
	}
	
	float3 uvs;			

	#if 0
		uvs = SSR_ComputeGrabScreenPos(CameraToScreenPosCheap(finalPosClip));
	#else
		float4 finalPosWorld = mul(UNITY_MATRIX_I_V, finalPos);
		float4 finalPosClip = mul(UNITY_MATRIX_VP, finalPosWorld);
		uvs = SSR_ComputeGrabScreenPos(finalPosClip.xyw);
	#endif

	uvs.xy = uvs.xy / uvs.z;
				
	#if defined(UNITY_STEREO_INSTANCING_ENABLED) || defined(UNITY_STEREO_MULTIVIEW_ENABLED)
	float xfade = smoothstep(0, 0.1, unity_StereoEyeIndex == 0 ? uvs.x : 1.0 - uvs.x);
	#else
	float xfade = smoothstep(0, 0.1, uvs.x)*smoothstep(1, 1- 0.1, uvs.x);
	#endif
	float yfade = smoothstep(0, 0.1, uvs.y)*smoothstep(1, 1- 0.1, uvs.y);
	xfade *= xfade;
	yfade *= yfade;
	
	float fade = saturate(2*(RdotV)) * xfade * yfade;
	
	float rayTanAngle2 = TanPhongConeAngle(data.perceptualRoughness * data.perceptualRoughness);
	float roughRadius = rayTanAngle2 * totalDistance;
	
	//float roughRatio = roughRadius * abs(UNITY_MATRIX_P._m11) / length(finalPos);
	//float blur = min(log2(_CameraOpaqueTexture_Dim.y * roughRatio), _CameraOpaqueTexture_Dim.z);
	//float4 reflection = SAMPLE_TEXTURE2D_X_LOD(_CameraOpaqueTexture, sampler_TrilinearClamp, uvs.xy, blur);
    float4 reflection = tex2Dlod(_GrabTexture, float4(uvs.xy, 0, 0));
	
	return float4(reflection.rgb, fade);
}

#endif // WATER_SSR