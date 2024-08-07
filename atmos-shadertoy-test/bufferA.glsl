#include "common.glsl"

// transmittance LUT: irrelevant to sun
// each pixel coordinate corresponds to a height and sun zenith angle
// does NOT need to update when the sun changes its angle
// need to be updated when the properties of the atmosphere changes
const int sunTransmittanceSteps = 40;

vec3 getSunTransmittance(vec3 pos, vec3 sunDir) {
  if (rayIntersectSphere(pos, sunDir, kGroundRadiusMm) > 0.0) {
    return vec3(0.0);
  }

  float atmoDist = rayIntersectSphere(pos, sunDir, kAtmosphereRadiusMm);

  // equation 2 from the paper
  vec3 sumOfExtinction = vec3(0.0);

  float stepLen = atmoDist / float(sunTransmittanceSteps);
  vec3 unitStep = stepLen * sunDir;
  vec3 marchedPos = pos - 0.5 * unitStep;
  for (int stepI = 0; stepI < sunTransmittanceSteps; stepI += 1) {
    marchedPos += unitStep;

    vec3 rayleighScattering, extinction;
    float mieScattering;
    getScatteringValues(marchedPos, rayleighScattering, mieScattering,
                        extinction);

    sumOfExtinction += extinction;
  }
  return exp(-stepLn * sumOfExtinction);
}

void mainImage(out vec4 fragColor, vec2 fragCoord) {
  if (any(greaterThanEqual(fragCoord.xy, kTLutRes.xy))) {
    return;
  }
  vec2 uv = fragCoord / kTLutRes;

  // [-1, 1)
  float sunCosTheta = 2.0 * uv.x - 1.0;
  // the result of arccos lays in [0, pi]
  // [pi, 0)
  float sunTheta = acos(sunCosTheta);
  // [kGroundRadius, kAtmosRadius)
  float height = mix(kGroundRadiusMm, kAtmosphereRadiusMm, uv.y);

  vec3 pos = vec3(0.0, height, 0.0);
  vec3 sunDir = normalize(vec3(0.0, sunCosTheta, -sin(sunTheta)));

  fragColor = vec4(getSunTransmittance(pos, sunDir), 1.0);
}
