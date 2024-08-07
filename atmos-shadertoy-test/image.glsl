#include "./core/color.glsl"
#include "./core/debug.glsl"
#include "./core/postprocessing.glsl"

#include "common.glsl"

#iChannel0 "./bufferA.glsl"
#iChannel1 "./bufferC.glsl"

/*
 * Partial implementation of
 *    "A Scalable and Production Ready Sky and Atmosphere Rendering Technique"
 *    by Sébastien Hillaire (2020).
 * Very much referenced and copied Sébastien's provided code:
 *    https://github.com/sebh/UnrealEngineSkyAtmosphere
 *    https://sebh.github.io/publications/egsr2020.pdf
 *
 * This basically implements the generation of a sky-view LUT, so it doesn't
 * include aerial perspective. It only works for views inside the atmosphere,
 * because the code assumes that the ray-marching starts at the camera position.
 * For a planetary view you'd want to check that and you might march from, e.g.
 * the edge of the atmosphere to the ground (rather than the camera position
 * to either the ground or edge of the atmosphere).
 *
 * Also want to cite:
 *    https://www.shadertoy.com/view/tdSXzD
 * Used the jodieReinhardTonemap from there, but that also made
 * me realize that the paper switched the Mie and Rayleigh camHeight densities
 * (which was confirmed after reading Sébastien's code more closely).
 */

float azimuthToUvX(float azimuth) { return (azimuth / PI + 1.0) * 0.5; }

// see section 5.3
// input:  [-0.5pi, 0.5pi)
// output: [0, 1)
// non-linear encoding
float altitudeToUvY(float altitude) {
  return 0.5 + 0.5 * sign(altitude) * sqrt(abs(altitude) * 2.0 / PI);
}

/*
 * Final output basically looks up the value from the skyLUT, and then adds a
 * sun on top, does some tonemapping.
 */
vec3 getValFromSkyLUT(vec3 rayDir, vec3 sunDir) {
  float camHeight = length(kCamPos);

  // the ray altitude, relative to the up vec of the cam
  // (-0.5pi, 0.5pi)
  float rayAlt = asin(rayDir.y);

  // (0, 2pi)
  float azimuth;
  // looking straight up or down
  azimuth = atan(rayDir.x, rayDir.z);
  vec2 uv = vec2(azimuthToUvX(azimuth), altitudeToUvY(rayAlt));

  uv *= kSkyLutRes;
  uv /= iChannelResolution[1].xy;

  uv = clamp(uv, vec2(1e-3), vec2(0.99));

  return texture(iChannel1, uv).rgb;
}

vec3 jodieReinhardTonemap(vec3 c) {
  // From: https://www.shadertoy.com/view/tdSXzD
  float l = lum(c);
  vec3 tc = c / (c + 1.0);
  return mix(c / (l + 1.0), tc, tc);
}

vec3 sunWithBloom(vec3 rayDir, vec3 sunDir) {
  const float sunSolidAngle = 0.53 * PI / 180.0;
  const float minSunCosTheta = cos(sunSolidAngle);

  float cosTheta = dot(rayDir, sunDir);
  if (cosTheta >= minSunCosTheta)
    return vec3(1.0);

  float offset = minSunCosTheta - cosTheta;
  float gaussianBloom = exp(-offset * 50000.0) * 0.5;
  float invBloom = 1.0 / (0.02 + offset * 300.0) * 0.01;
  return vec3(gaussianBloom + invBloom);
}

void mainImage(out vec4 fragColor, vec2 fragCoord) {
  vec2 uv = fragCoord / iResolution.xy;

  vec3 sunDir = getSunDir(getSunAltitude(iMouse.x / iResolution.x));

  vec3 camDir = normalize(vec3(0.0, 0.27, -1.0));
  float camVFov = 0.2 * PI;
  float camVExtent = 2.0 * tan(camVFov / 2.0);
  float camWExtent = camVExtent * iResolution.x / iResolution.y;

  vec3 camRight = normalize(cross(camDir, vec3(0.0, 1.0, 0.0)));
  vec3 camcamUp = normalize(cross(camRight, camDir));

  vec2 uvRemapped = 2.0 * uv - 1.0;
  vec3 rayDir = normalize(camDir + camRight * uvRemapped.x * camWExtent +
                          camcamUp * uvRemapped.y * camVExtent);

  vec3 lum = getValFromSkyLUT(rayDir, sunDir);

  // bloom should be added at the end, but this is subtle and works well.
  vec3 sunLum = sunWithBloom(rayDir, sunDir);
  // use smoothstep to limit the effect, so it drops off to actual zero.
  sunLum = smoothstep(0.002, 1.0, sunLum);
  if (length(sunLum) > 0.0) {
    if (rayIntersectSphere(kCamPos, rayDir, kGroundRadiusMm) >= 0.0) {
      sunLum *= 0.0;
    } else {
      // If the sun value is applied to this pixel, we need to calculate the
      // transmittance to obscure it.
      sunLum *=
          getValFromTLUT(iChannel0, iChannelResolution[0].xy, kCamPos, sunDir);
    }
  }
  lum += sunLum;

  // tonemapping and gamma. ScamUper ad-hoc, probably a better way to do this.
  lum *= 20.0;
  lum = pow(lum, vec3(1.3));
  lum /= (smoothstep(0.0, 0.2, clamp(sunDir.y, 0.0, 1.0)) * 2.0 + 0.15);

  lum = jodieReinhardTonemap(lum);

  lum = pow(lum, vec3(1.0 / 2.2));

  // apply dithering to avoid color band effect
  lum += getDitherMask(ivec2(fragCoord.xy));

  fragColor = vec4(lum, 1.0);

  float isDigit = printValue((fragCoord - vec2(10.0)) / vec2(8.0, 15.0),
                             iMouse.x / iResolution.x, 5.0, 3.0);
  fragColor = mix(fragColor, vec4(0.0, 1.0, 0.0, 1.0), isDigit);
}
