
const float PI = 3.14159265358;

// units are in megameters.
const float kGroundRadiusMm = 6.36;
const float kAtmosphereRadiusMm = 6.46;

// 200m above the ground.
const vec3 kViewPos = vec3(0.0, kGroundRadiusMm + 0.0002, 0.0);

const vec2 kTLutRes = vec2(256.0, 64.0);
const vec2 kMsLutRes = vec2(32.0);
const vec2 kSkyLutRes = vec2(200.0);

const vec3 kGroundAlbedo = vec3(0.3);

// found in sec 4, table 1
const vec3 kRayleighScatteringBase = vec3(5.802, 13.558, 33.1);
// rayleigh does not absorb

const float kMieScatteringBase = 3.996;
const float kMieAbsorptionBase = 4.4;

// ozone does not scatter
const vec3 kOzoneAbsorptionBase = vec3(0.650, 1.881, 0.085);

float _getSunAltitude(float sunPos, vec2 iResolution) {
  return (sunPos * 2.0 - 1.0) * PI;
}

vec3 getSunDir(float sunPos, vec2 iResolution) {
  float altitude = _getSunAltitude(sunPos, iResolution);
  return normalize(vec3(0.0, sin(altitude), -cos(altitude)));
}

float getRayleighPhase(float cosTheta) {
  const float k = 3.0 / (16.0 * PI);
  return k * (1.0 + cosTheta * cosTheta);
}

float getMiePhase(float cosTheta) {
  const float g = 0.8;
  const float scale = 3.0 / (8.0 * PI);

  float num = (1.0 - g * g) * (1.0 + cosTheta * cosTheta);
  float denom = (2.0 + g * g) * pow((1.0 + g * g - 2.0 * g * cosTheta), 1.5);

  return scale * num / denom;
}

void getScatteringValues(vec3 pos, out vec3 oRayleighScattering,
                         out float oMieScattering, out vec3 oExtinction) {
  float altitudeKM = (length(pos) - kGroundRadiusMm) * 1000.0;

  float rayleighDensity = exp(-altitudeKM * 0.125);
  float mieDensity = exp(-altitudeKM * 0.833);

  oRayleighScattering = kRayleighScatteringBase * rayleighDensity;

  oMieScattering = kMieScatteringBase * mieDensity;
  float mieAbsorption = kMieAbsorptionBase * mieDensity;

  // ozone does not scatter
  vec3 ozoneAbsorption =
      kOzoneAbsorptionBase * max(0.0, 1.0 - abs(altitudeKM - 25.0) / 15.0);

  // the sum of all scattering and obsorbtion
  oExtinction =
      oRayleighScattering + oMieScattering + mieAbsorption + ozoneAbsorption;
}

float safeacos(const float x) { return acos(clamp(x, -1.0, 1.0)); }

// returns: -1 - when no hitting point, or the distance to the closest hit of
// the sphere
float rayIntersectSphere(vec3 ro, vec3 rd, float radius) {
  float t = -dot(ro, rd);
  float b2 = dot(ro, ro);
  float c = b2 - radius * radius;

  // if rd is outside the sphere, and the ray is departuring the sphere, we can
  // apply a fast culling
  if (c > 0.0 && t < 0.0) {
    return -1.0;
  }

  float discr = t * t - c;
  // no hit at all
  if (discr < 0.0) {
    return -1.0;
  }

  float h = sqrt(discr);
  // outside sphere, use near insec point
  if (c > 0.0) {
    return t - h;
  }
  // inside sphere, use far insec point
  return t + h;
}

vec3 getValFromTLUT(sampler2D tex, vec2 bufferRes, vec3 pos, vec3 sunDir) {
  float height = length(pos);
  // the normalized up vector
  vec3 up = pos / height;
  // theta is the angle from up vector to sun vector
  float sunCosTheta = dot(sunDir, up);
  vec2 uv = vec2(0.5 * sunCosTheta + 0.5,
                 (height - kGroundRadiusMm) /
                     (kAtmosphereRadiusMm - kGroundRadiusMm));
  uv = clamp(uv, vec2(0.0), vec2(1.0));
  uv *= kTLutRes / bufferRes;
  return texture(tex, uv).rgb;
}

vec3 getValFromMultiScattLUT(sampler2D tex, vec2 bufferRes, vec3 pos,
                             vec3 sunDir) {
  float height = length(pos);
  vec3 up = pos / height;
  float sunCosTheta = dot(sunDir, up);
  vec2 uv = vec2(0.5 * sunCosTheta + 0.5,
                 (height - kGroundRadiusMm) /
                     (kAtmosphereRadiusMm - kGroundRadiusMm));
  uv = clamp(uv, vec2(0.0), vec2(1.0));
  uv *= kMsLutRes / bufferRes;
  return texture(tex, uv).rgb;
}
