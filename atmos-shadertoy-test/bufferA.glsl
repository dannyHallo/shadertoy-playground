#include "common.glsl"

// the transmittance LUT:
// each pixel coordinate corresponds to a height and sun zenith angle, and the
// value is the transmittance from that point to sun, through the atmosphere.
const float sunTransmittanceSteps = 40.0;

vec3 getSunTransmittance(vec3 pos, vec3 sunDir) {
  if (rayIntersectSphere(pos, sunDir, kGroundRadiusMm) > 0.0) {
    return vec3(0.0);
  }

  float atmoDist = rayIntersectSphere(pos, sunDir, kAtmosphereRadiusMm);

  // equation 2 from the paper
  vec3 sumOfExtinction = vec3(0.0);
  float dt = atmoDist / sunTransmittanceSteps;
  for (float i = 0.0; i < sunTransmittanceSteps; i += 1.0) {
    vec3 newPos = pos + dt * (i + 0.5) * sunDir;

    vec3 rayleighScattering, extinction;
    float mieScattering;
    getScatteringValues(newPos, rayleighScattering, mieScattering, extinction);

    sumOfExtinction += extinction;
  }
  return exp(-sumOfExtinction * dt);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
  if (any(greaterThanEqual(fragCoord.xy, kTLutRes.xy))) {
    return;
  }
  vec2 uv = fragCoord / kTLutRes;

  float sunCosTheta = 2.0 * uv.x - 1.0;
  float sunTheta = acos(sunCosTheta);
  float height = mix(kGroundRadiusMm, kAtmosphereRadiusMm, uv.y);

  vec3 pos = vec3(0.0, height, 0.0);
  vec3 sunDir = normalize(vec3(0.0, sunCosTheta, -sin(sunTheta)));

  fragColor = vec4(getSunTransmittance(pos, sunDir), 1.0);
}
