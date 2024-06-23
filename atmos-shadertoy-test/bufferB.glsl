#include "common.glsl"

#iChannel0 "./bufferA.glsl"

// multi-scattering approximation LUT
// each pixel coordinate corresponds to a height and sun zenith angle
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
  vec3 fractionOfLightScattered = vec3(0.0);

  float sampleCountInv = 1.0 / float(sampleCountSqrt * sampleCountSqrt);
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

      float rayleighPhaseValue = getRayleighPhase(cosTheta);
      float miePhaseValue = getMiePhase(cosTheta);

      vec3 lum = vec3(0.0);
      vec3 lumFactor = vec3(0.0);
      vec3 upToDateTransmittance = vec3(1.0);
      float dt = tMax / mulScattSteps;
      for (float stepI = 0.0; stepI < mulScattSteps; stepI += 1.0) {
        vec3 marchedPos = pos + dt * (stepI + 0.5) * rayDir;

        vec3 rayleighScattering, extinction;
        float mieScattering;
        getScatteringValues(marchedPos, rayleighScattering, mieScattering,
                            extinction);

        // transmittance in unit length, at current pos
        vec3 transmittedOverDt = exp(-dt * extinction);

        vec3 scatteredOrAbsorbedOverDt = 1.0 - transmittedOverDt;

        vec3 scatteringNoPhase = rayleighScattering + mieScattering;
        vec3 scatteringF =
            scatteredOrAbsorbedOverDt * scatteringNoPhase / extinction;

        upToDateTransmittance *= transmittedOverDt;
        lumFactor += upToDateTransmittance * scatteringF;

        vec3 rayleighInScattering = rayleighScattering * rayleighPhaseValue;
        float mieInScattering = mieScattering * miePhaseValue;

        // eq 6, with correction to the paper: S(x,w_s) should be S(x-tv,w_s).
        vec3 sunTransmittance = getValFromTLUT(
            iChannel0, iChannelResolution[0].xy, marchedPos, sunDir);
        vec3 inScattering =
            (rayleighInScattering + mieInScattering) * sunTransmittance;

        // integrated scattering within path segment
        vec3 scatteringIntegral =
            scatteredOrAbsorbedOverDt * inScattering / extinction;

        lum += upToDateTransmittance * scatteringIntegral;
      }

      if (hitsGround) {
        vec3 hitPos = pos + groundDist * rayDir;
        if (dot(pos, sunDir) > 0.0) {
          hitPos = normalize(hitPos) * kGroundRadiusMm;
          lum += upToDateTransmittance * kGroundAlbedo *
                 getValFromTLUT(iChannel0, iChannelResolution[0].xy, hitPos,
                                sunDir);
        }
      }

      fractionOfLightScattered += lumFactor * sampleCountInv;
      secondOrderLum += lum * sampleCountInv;
    }
  }

  // eq 10: calculates psi
  return secondOrderLum / (1.0 - fractionOfLightScattered);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
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
