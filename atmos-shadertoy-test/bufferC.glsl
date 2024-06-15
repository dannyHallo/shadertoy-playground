#include "common.glsl"

#iChannel0 "./bufferA.glsl"
#iChannel1 "./bufferB.glsl"

// Buffer C calculates the actual sky-view! It's a lat-long map (or maybe
// altitude-azimuth is the better term), but the latitude/altitude is non-linear
// to get more resolution near the horizon.
const int numScatteringSteps = 32;
vec3 raymarchScattering(vec3 pos, vec3 rayDir, vec3 sunDir, float tMax,
                        float numSteps) {
  float cosTheta = dot(rayDir, sunDir);

  float miePhaseValue = getMiePhase(cosTheta);
  float rayleighPhaseValue = getRayleighPhase(-cosTheta);

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
  if (fragCoord.x >= (kSkyLutRes.x + 1.5) ||
      fragCoord.y >= (kSkyLutRes.y + 1.5)) {
    return;
  }

  float u = clamp(fragCoord.x, 0.0, kSkyLutRes.x - 1.0) / kSkyLutRes.x;
  float v = clamp(fragCoord.y, 0.0, kSkyLutRes.y - 1.0) / kSkyLutRes.y;

  float azimuthAngle = ((u * 2.0) - 1.0) * PI;

  // Non-linear mapping of altitude. See Section 5.3 of the paper.
  float adjV;
  if (v < 0.5) {
    float coord = 1.0 - 2.0 * v;
    adjV = -coord * coord;
  } else {
    float coord = v * 2.0 - 1.0;
    adjV = coord * coord;
  }

  float height = length(kViewPos);
  vec3 up = kViewPos / height;

  // float horizonAngle = safeacos(sqrt(height * height - groundRadiusMM *
  // groundRadiusMM) / height) - 0.5*PI;
  float horizonAngle = asin(kGroundRadiusMM / height) - 0.5 * PI;
  float altitudeAngle = adjV * 0.5 * PI - horizonAngle;

  float cosAltitude = cos(altitudeAngle);
  vec3 rayDir = vec3(cosAltitude * sin(azimuthAngle), sin(altitudeAngle),
                     -cosAltitude * cos(azimuthAngle));

  float sunAltitude =
      (0.5 * PI) -
      acos(dot(getSunDir(iMouse.x / iResolution.x, iResolution.xy), up));
  vec3 sunDir = vec3(0.0, sin(sunAltitude), -cos(sunAltitude));

  float atmoDist = rayIntersectSphere(kViewPos, rayDir, kAtmosphereRadiusMM);
  float groundDist = rayIntersectSphere(kViewPos, rayDir, kGroundRadiusMM);
  float tMax = (groundDist < 0.0) ? atmoDist : groundDist;
  vec3 lum = raymarchScattering(kViewPos, rayDir, sunDir, tMax,
                                float(numScatteringSteps));
  fragColor = vec4(lum, 1.0);
}
