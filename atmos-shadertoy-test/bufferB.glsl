#include "common.glsl"

#iChannel0 "./bufferA.glsl"

// multi-scattering approximation LUT
// each pixel coordinate corresponds to a height and sun zenith angle
// does NOT need to update when the sun changes its angle
// need to be updated when the properties of the atmosphere changes
const float mulScattSteps = 20.0;
const int sampleCountSqrt = 8;

vec3 getSphericalDir(float theta, float phi) {
  float sinPhi = sin(phi);
  return vec3(sinPhi * sin(theta), cos(phi), sinPhi * cos(theta));
}

// eq 5 & 7
// returns psi
vec3 getMulScattValues(vec3 pos, vec3 sunDir) {
  vec3 secondOrderLum = vec3(0.0);
  // multi-scattering factor, aka f_ms
  vec3 msFac = vec3(0.0);

  const float sampleCountInv = 1.0 / float(sampleCountSqrt * sampleCountSqrt);

  // take uniform samples over all directions around a sphere, then calc avg
  for (int i = 0; i < sampleCountSqrt; i++) {
    for (int j = 0; j < sampleCountSqrt; j++) {
      // (0 -> 1) for each component
      vec2 ij01 = (vec2(i, j) + vec2(0.5)) / float(sampleCountSqrt);
      // (0 -> pi), uniform:
      // this integral is symmetric about theta = 0 (or theta = PI), so we
      // only need to integrate from zero to PI, not zero to 2*PI
      float theta = PI * ij01.x;

      // (1 -> -1) -->acos--> (0 -> pi), uniform before acos
      float phi = acos(1.0 - 2.0 * ij01.y);
      vec3 rayDir = getSphericalDir(theta, phi);

      float atmosDist = rayIntersectSphere(pos, rayDir, kAtmosphereRadiusMm);
      float groundDist = rayIntersectSphere(pos, rayDir, kGroundRadiusMm);

      bool hitsGround = groundDist > 0.0;
      float tMax = hitsGround ? groundDist : atmosDist;

      float cosTheta = dot(rayDir, sunDir);

      // d prefix denotes directional
      float dRayleighPhaseVal = getRayleighPhase(cosTheta);
      float dMiePhaseVal = getMiePhase(cosTheta);

      vec3 dSecondOrderLum = vec3(0.0);
      // quantifies the proportion of light that contributes to multiple
      // scattering in a given direction
      vec3 dMsFac = vec3(0.0);
      vec3 dUpToDateTransmittance = vec3(1.0);

      float dt = tMax / mulScattSteps;

      for (float stepI = 0.0; stepI < mulScattSteps; stepI += 1.0) {
        vec3 marchedPos = pos + dt * (stepI + 0.5) * rayDir;

        vec3 rayleighScattering;
        float mieScattering;
        vec3 extinction; // extent of being absorbed or scattered
        getScatteringValues(marchedPos, rayleighScattering, mieScattering,
                            extinction);

        // transmittance in unit length, at current pos
        vec3 transmittedOverDt = exp(-dt * extinction);
        vec3 scatteredOrAbsorbedOverDt = 1.0 - transmittedOverDt;

        vec3 scatteredExtinction = rayleighScattering + mieScattering;
        // calculates the overall proportion of light that's been scattered over
        // dt, without considering phase (angle)
        vec3 scatteredOverDt =
            scatteredOrAbsorbedOverDt * (scatteredExtinction / extinction);

        dUpToDateTransmittance *= transmittedOverDt;
        dMsFac += dUpToDateTransmittance * scatteredOverDt;

        vec3 rayleighInScattering = rayleighScattering * dRayleighPhaseVal;
        float mieInScattering = mieScattering * dMiePhaseVal;

        // eq 6, with correction to the paper: S(x,w_s) should be S(x-tv,w_s).
        vec3 sunTransmittance = getValFromTLUT(
            iChannel0, iChannelResolution[0].xy, marchedPos, sunDir);
        vec3 inScattering =
            (rayleighInScattering + mieInScattering) * sunTransmittance;

        // calculates the proportion of light that's been scattered in this
        // particular angle
        vec3 scatteringIntegral =
            scatteredOrAbsorbedOverDt * (inScattering / extinction);

        dSecondOrderLum += dUpToDateTransmittance * scatteringIntegral;
      }

      if (hitsGround) {
        vec3 hitPos = pos + groundDist * rayDir;
        if (dot(pos, sunDir) > 0.0) {
          // hitPos = normalize(hitPos) * kGroundRadiusMm;
          dSecondOrderLum += dUpToDateTransmittance * kGroundAlbedo *
                             getValFromTLUT(iChannel0, iChannelResolution[0].xy,
                                            hitPos, sunDir);
        }
      }

      msFac += dMsFac;
      secondOrderLum += dSecondOrderLum;
    }
  }
  msFac *= sampleCountInv;
  secondOrderLum *= sampleCountInv;

  // eq 10: calculates psi
  return secondOrderLum / (1.0 - msFac);
}

void mainImage(out vec4 fragColor, vec2 fragCoord) {
  if (any(greaterThanEqual(fragCoord.xy, kMsLutRes.xy))) {
    return;
  }
  vec2 uv = fragCoord / kMsLutRes;

  float sunCosTheta = 2.0 * uv.x - 1.0;
  float sunTheta = acos(sunCosTheta);
  float height = mix(kGroundRadiusMm, kAtmosphereRadiusMm, uv.y);

  vec3 pos = vec3(0.0, height, 0.0);
  vec3 sunDir = normalize(vec3(0.0, sunCosTheta, -sin(sunTheta)));

  fragColor = vec4(getMulScattValues(pos, sunDir), 1.0);
}
