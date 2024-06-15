
const float PI = 3.14159265358;

// Units are in megameters.
const float kGroundRadiusMM = 6.36;
const float kAtmosphereRadiusMM = 6.46;

// 200M above the ground.
const vec3 kViewPos = vec3(0.0, kGroundRadiusMM + 0.0002, 0.0);

const vec2 kTLutRes = vec2(256.0, 64.0);
const vec2 kMsLutRes = vec2(32.0, 32.0);
// Doubled the vertical skyLUT res from the paper, looks way
// better for sunrise.
const vec2 kSkyLutRes = vec2(200.0, 200.0);

const vec3 kGroundAlbedo = vec3(0.3);

// These are per megameter.
const vec3 kRayleighScatteringBase = vec3(5.802, 13.558, 33.1);
const float kRayleighAbsorptionBase = 0.0;

const float kMieScatteringBase = 3.996;
const float kMieAbsorptionBase = 4.4;

const vec3 kOzoneAbsorptionBase = vec3(0.650, 1.881, .085);

float _getSunAltitude(vec2 iMouse, vec2 iResolution) {
  float mouse01 = iMouse.y / iResolution.y;
  return (mouse01 * 2.0 - 1.0) * PI;
}

vec3 getSunDir(vec2 iMouse, vec2 iResolution) {
  float altitude = _getSunAltitude(iMouse, iResolution);
  return normalize(vec3(0.0, sin(altitude), -cos(altitude)));
}

float getMiePhase(float cosTheta) {
  const float g = 0.8;
  const float scale = 3.0 / (8.0 * PI);

  float num = (1.0 - g * g) * (1.0 + cosTheta * cosTheta);
  float denom = (2.0 + g * g) * pow((1.0 + g * g - 2.0 * g * cosTheta), 1.5);

  return scale * num / denom;
}

float getRayleighPhase(float cosTheta) {
  const float k = 3.0 / (16.0 * PI);
  return k * (1.0 + cosTheta * cosTheta);
}

void getScatteringValues(vec3 pos, out vec3 rayleighScattering,
                         out float mieScattering, out vec3 extinction) {
  float altitudeKM = (length(pos) - kGroundRadiusMM) * 1000.0;

  float rayleighDensity = exp(-altitudeKM * 0.125);
  float mieDensity = exp(-altitudeKM * 0.833);

  rayleighScattering = kRayleighScatteringBase * rayleighDensity;
  float rayleighAbsorption = kRayleighAbsorptionBase * rayleighDensity;

  mieScattering = kMieScatteringBase * mieDensity;
  float mieAbsorption = kMieAbsorptionBase * mieDensity;

  vec3 ozoneAbsorption =
      kOzoneAbsorptionBase * max(0.0, 1.0 - abs(altitudeKM - 25.0) / 15.0);

  extinction = rayleighScattering + rayleighAbsorption + mieScattering +
               mieAbsorption + ozoneAbsorption;
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
  vec3 up = pos / height;
  float sunCosZenithAngle = dot(sunDir, up);
  vec2 uv =
      vec2(kTLutRes.x * clamp(0.5 + 0.5 * sunCosZenithAngle, 0.0, 1.0),
           kTLutRes.y *
               max(0.0, min(1.0, (height - kGroundRadiusMM) /
                                     (kAtmosphereRadiusMM - kGroundRadiusMM))));
  uv /= bufferRes;
  return texture(tex, uv).rgb;
}

vec3 getValFromMultiScattLUT(sampler2D tex, vec2 bufferRes, vec3 pos,
                             vec3 sunDir) {
  float height = length(pos);
  vec3 up = pos / height;
  float sunCosZenithAngle = dot(sunDir, up);
  vec2 uv =
      vec2(kMsLutRes.x * clamp(0.5 + 0.5 * sunCosZenithAngle, 0.0, 1.0),
           kMsLutRes.y *
               max(0.0, min(1.0, (height - kGroundRadiusMM) /
                                     (kAtmosphereRadiusMM - kGroundRadiusMM))));
  uv /= bufferRes;
  return texture(tex, uv).rgb;
}
