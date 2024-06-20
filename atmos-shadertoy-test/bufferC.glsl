#include "common.glsl"

#iChannel0 "./bufferA.glsl"
#iChannel1 "./bufferB.glsl"

// buffer C calculates the actual sky-view
// it's a non-linear lat-long (altitude-azimuth) map, and has more resolution
// near the horizon.
const int numScatteringSteps = 32;
vec3 raymarchScattering(vec3 pos, vec3 rayDir, vec3 sunDir, float tMax,
                        float numSteps) {
  float cosTheta = dot(rayDir, sunDir);

  float miePhaseValue = getMiePhase(cosTheta);
  float rayleighPhaseValue = getRayleighPhase(cosTheta);

  vec3 lum = vec3(0.0);
  vec3 transmittance = vec3(1.0);
  float t = 0.0;
  for (float i = 0.0; i < numSteps; i += 1.0) {
    float newT = ((i + 0.3) / numSteps) * tMax;
    float dt = newT - t;
    t = newT;

    vec3 newPos = pos + t * rayDir;

    vec3 rayleighScattering, extinction;
    float mieScattering;
    getScatteringValues(newPos, rayleighScattering, mieScattering, extinction);

    vec3 sampleTransmittance = exp(-dt * extinction);

    vec3 sunTransmittance =
        getValFromTLUT(iChannel0, iChannelResolution[0].xy, newPos, sunDir);
    vec3 psiMS = getValFromMultiScattLUT(iChannel1, iChannelResolution[1].xy,
                                         newPos, sunDir);

    vec3 rayleighInScattering =
        rayleighScattering * (rayleighPhaseValue * sunTransmittance + psiMS);
    vec3 mieInScattering =
        mieScattering * (miePhaseValue * sunTransmittance + psiMS);
    vec3 inScattering = (rayleighInScattering + mieInScattering);

    // Integrated scattering within path segment.
    vec3 scatteringIntegral =
        (inScattering - inScattering * sampleTransmittance) / extinction;

    lum += scatteringIntegral * transmittance;

    transmittance *= sampleTransmittance;
  }
  return lum;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
  if (any(greaterThanEqual(fragCoord.xy, kSkyLutRes.xy))) {
    return;
  }

  vec2 uv = fragCoord / kSkyLutRes;

  // -PI to PI
  float azimuthAngle = ((uv.x * 2.0) - 1.0) * PI;

  // non-linear mapping of altitude
  // see section 5.3 of the paper
  float adjV;
  if (uv.y < 0.5) {
    float coord = 1.0 - 2.0 * uv.y;
    adjV = -coord * coord;
  } else {
    float coord = uv.y * 2.0 - 1.0;
    adjV = coord * coord;
  }
  adjV *= 0.5 * PI;

  float height = length(kViewPos);
  vec3 up = kViewPos / height;

  // float horizonAngle = safeacos(sqrt(height * height - groundRadiusMM *
  // groundRadiusMM) / height) - 0.5*PI;
  float horizonAngle = 0.5 * PI - asin(kGroundRadiusMm / height);
  float altitudeAngle = adjV + horizonAngle;

  float cosAltitude = cos(altitudeAngle);
  // TODO: there's a problem at the dir
  vec3 rayDir = vec3(cosAltitude * sin(azimuthAngle), sin(altitudeAngle),
                     -cosAltitude * cos(azimuthAngle));

  float sunAltitude =
      (0.5 * PI) -
      acos(dot(getSunDir(iMouse.x / iResolution.x, iResolution.xy), up));
  vec3 sunDir = vec3(0.0, sin(sunAltitude), -cos(sunAltitude));

  float atmoDist = rayIntersectSphere(kViewPos, rayDir, kAtmosphereRadiusMm);
  float groundDist = rayIntersectSphere(kViewPos, rayDir, kGroundRadiusMm);
  float tMax = (groundDist < 0.0) ? atmoDist : groundDist;
  vec3 lum = raymarchScattering(kViewPos, rayDir, sunDir, tMax,
                                float(numScatteringSteps));
  fragColor = vec4(lum, 1.0);
}
