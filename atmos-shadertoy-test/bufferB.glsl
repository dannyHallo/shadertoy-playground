#include "common.glsl"

#iChannel0 "./bufferA.glsl"

// multi-scattering approximation LUT
// each pixel coordinate corresponds to a height and sun zenith angle
const float mulScattSteps = 20.0;
const int sqrtSamples = 8;

vec3 getSphericalDir(float theta, float phi) {
  float sinPhi = sin(phi);
  return vec3(sinPhi * sin(theta), cos(phi), sinPhi * cos(theta));
}

// calculates equation (5) and (7) from the paper.
void getMulScattValues(vec3 pos, vec3 sunDir, out vec3 lumTotal, out vec3 fms) {
  lumTotal = vec3(0.0);
  fms = vec3(0.0);

  float invSamples = 1.0 / float(sqrtSamples * sqrtSamples);
  for (int i = 0; i < sqrtSamples; i++) {
    for (int j = 0; j < sqrtSamples; j++) {
      // this integral is symmetric about theta = 0 (or theta = PI), so we
      // only need to integrate from zero to PI, not zero to 2*PI.

      // (0 -> 1) for each component
      vec2 ij01 = (vec2(i, j) + vec2(0.5)) / float(sqrtSamples);
      // (0 -> pi), uniform
      float theta = PI * ij01.x;

      // (1 -> -1) -->acos--> (0 -> pi), uniform before acos
      float phi = safeacos(1.0 - 2.0 * ij01.y);
      vec3 rayDir = getSphericalDir(theta, phi);

      float atmosDist = rayIntersectSphere(pos, rayDir, kAtmosphereRadiusMm);
      float groundDist = rayIntersectSphere(pos, rayDir, kGroundRadiusMm);

      bool hitsGround = groundDist > 0.0;
      float tMax = hitsGround ? groundDist : atmosDist;

      float cosTheta = dot(rayDir, sunDir);

      float rayleighPhaseValue = getRayleighPhase(cosTheta);
      float miePhaseValue = getMiePhase(cosTheta);

      vec3 lum = vec3(0.0), lumFactor = vec3(0.0), transmittance = vec3(1.0);
      float t = 0.0;
      for (float stepI = 0.0; stepI < mulScattSteps; stepI += 1.0) {
        float newT = ((stepI + 0.3) / mulScattSteps) * tMax;
        float dt = newT - t;
        t = newT;
        vec3 newPos = pos + t * rayDir;

        vec3 rayleighScattering, extinction;
        float mieScattering;
        getScatteringValues(newPos, rayleighScattering, mieScattering,
                            extinction);

        vec3 sampleTransmittance = exp(-dt * extinction);

        // Integrate within each segment.
        vec3 scatteringNoPhase = rayleighScattering + mieScattering;
        vec3 scatteringF =
            (scatteringNoPhase - scatteringNoPhase * sampleTransmittance) /
            extinction;
        lumFactor += transmittance * scatteringF;

        // This is slightly different from the paper, but I think the paper has
        // a mistake? In equation (6), I think S(x,w_s) should be S(x-tv,w_s).
        vec3 sunTransmittance =
            getValFromTLUT(iChannel0, iChannelResolution[0].xy, newPos, sunDir);

        vec3 rayleighInScattering = rayleighScattering * rayleighPhaseValue;
        float mieInScattering = mieScattering * miePhaseValue;
        vec3 inScattering =
            (rayleighInScattering + mieInScattering) * sunTransmittance;

        // Integrated scattering within path segment.
        vec3 scatteringIntegral =
            (inScattering - inScattering * sampleTransmittance) / extinction;

        lum += scatteringIntegral * transmittance;
        transmittance *= sampleTransmittance;
      }

      if (groundDist > 0.0) {
        vec3 hitPos = pos + groundDist * rayDir;
        if (dot(pos, sunDir) > 0.0) {
          hitPos = normalize(hitPos) * kGroundRadiusMm;
          lum += transmittance * kGroundAlbedo *
                 getValFromTLUT(iChannel0, iChannelResolution[0].xy, hitPos,
                                sunDir);
        }
      }

      fms += lumFactor * invSamples;
      lumTotal += lum * invSamples;
    }
  }
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

  vec3 lum, fMs;
  getMulScattValues(pos, sunDir, lum, fMs);

  // Equation 10 from the paper.
  vec3 psi = lum / (1.0 - fMs);
  fragColor = vec4(psi, 1.0);
}
