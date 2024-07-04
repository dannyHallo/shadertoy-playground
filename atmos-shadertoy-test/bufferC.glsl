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

// see section 5.3
// input:  [0, 1)
// output: [-0.5pi, 0.5pi)
// non-linear encoding
float uvYToAltitude(float uvY) {
  float centeredY = uvY - 0.5;
  return sign(centeredY) * (centeredY * centeredY) * TWO_PI;
}

void mainImage(out vec4 fragColor, vec2 fragCoord) {
  if (any(greaterThanEqual(fragCoord.xy, kSkyLutRes.xy))) {
    return;
  }

  vec2 uv = fragCoord / kSkyLutRes;

  // get the altitude angle to pre-calculate of this pixel
  float alt = uvYToAltitude(uv.y);

  float camHeight = length(kCamPos);

  // [-pi, pi)
  float azi = (uv.x * 2.0 - 1.0) * PI;

  float cosAlt = cos(alt);
  vec3 rayDir = vec3(cosAlt * sin(azi), sin(alt), cosAlt * cos(azi));

  float groundDist = rayIntersectSphere(kCamPos, rayDir, kGroundRadiusMm);
  float tMax = groundDist >= 0.0
                   ? groundDist
                   : rayIntersectSphere(kCamPos, rayDir, kAtmosphereRadiusMm);

  vec3 sunDir = getSunDir(getSunAltitude(iMouse.x / iResolution.x));
  vec3 lum = raymarchScattering(kCamPos, rayDir, sunDir, tMax,
                                float(numScatteringSteps));
  fragColor = vec4(lum, 1.0);
}
