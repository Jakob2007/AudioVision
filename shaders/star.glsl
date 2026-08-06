#version ${GLSL_VERSION}
${PRECISION}
uniform float iTime;
uniform float iAlpha;
uniform vec2  iRes;
uniform sampler2D iFFT;
in  vec2 uv;
out vec4 fragColor;

#define PI     3.14159265
#define TWO_PI 6.28318530
#define N_RAYS 4

// ── FFT ──────────────────────────────────────────────────────────────────────

float fftAt(float x) {
    return texture(iFFT, vec2(clamp(x, 0.0, 1.0), 0.0)).r;
}

float bass() {
    float s = 0.0;
    for (int i = 0; i < 6; i++) s += fftAt(float(i) / 512.0);
    return s / 6.0;
}

float mid() {
    float s = 0.0;
    for (int i = 0; i < 6; i++) s += fftAt(0.08 + float(i) / 200.0);
    return s / 6.0;
}

// ── sinc envelope ─────────────────────────────────────────────────────────────
// sinc(x) = sin(x)/x, returns 1 at x=0
// Used to shape amplitude along the ray axis:
// strong at centre, decaying with oscillation toward the tip.

float sinc(float x) {
    if (abs(x) < 0.0001) return 1.0;
    return sin(x) / x;
}

// ── single wave line ──────────────────────────────────────────────────────────
// Computes brightness contribution of one sine wave in ray-local coords.
//
// u    : position along ray axis (0 = centre, grows toward tip)
// v    : position perpendicular to ray
// freq : spatial frequency of the sine wave along v
// phase: time-based phase offset
// chOffset: channel-specific lateral offset (creates RGB separation)
// b    : bass value
//
// Returns 0..1 brightness at this point.

float rand(vec2 co) {
    return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453);
}

float rand(float seed) {
    return rand(vec2(seed, seed));
}

float waveLine(float u, float v, float freq, float phase,
               float chOffset, float b, float j) {

    float i = j + .5;
    float envelope = abs(.3/u) * .1;

    // wave centre position oscillates along v with sinc amplitude
    float wave = 0;
    wave+= sin(u * freq + b + rand(phase)*.01) * envelope * (.2 + b * 2) * (1+chOffset*.2) * (.5 + chOffset)*.5q;
    wave+= cos(u * freq * 5 + i) * envelope * .2 * sin(u*freq+phase+i);
    wave+= rand(vec2(round(u*200)/200, round(phase*20)/20))*.01 * b * b;
    wave+= sin(u * freq * 10 + rand(phase*i)*2) * .01 * b;
    // wave+= pow(sin(u+phase), 17) * .1;
    float p = u*10 - sin(rand(round(phase)+i))*30;
    float f = (mod(phase+i, 1)) * freq * .3 * round(mod(phase+i, 2)-1) * b;
    wave+= pow(sin(p) / p, 3) * f * .2;

    // distance from this pixel to the wave centre
    float dist = abs(v - wave);

    // line thickness: thinner toward tip (scales with envelope)
    float thick = 0.013 + b * .05;

    float fade = smoothstep(0, .1, u);

    return max(thick-dist, 0) / thick * fade;
    return smoothstep(thick, 0.0, dist) * fade;
}

// ── ray contribution ──────────────────────────────────────────────────────────
// Computes the RGB colour contribution of one ray.
//
// p        : fragment position in world space (aspect-corrected)
// rayAngle : angle of this ray in radians (0=right, PI/2=up, etc.)
// b        : bass
// m        : mid

vec3 rayColour(vec2 p, float rayAngle, float b, float m) {
    // rotate p into ray-local coordinate system
    float cosA = cos(-rayAngle);
    float sinA = sin(-rayAngle);
    float u    = cosA * p.x - sinA * p.y;   // along ray
    float v    = sinA * p.x + cosA * p.y;   // perpendicular

    // multiple wave frequencies per ray for richness
    float t = iTime;

    // R channel: slightly lower frequency, offset to one side
    float rVal = waveLine(u, v, 4.2, t * 0.9,           -1.0, b, rayAngle);

    // G channel: medium frequency, centred
    float gVal = waveLine(u, v, 5.0, t * 0.85 + 0.7,     0.0, b, rayAngle);

    // B channel: slightly higher frequency, offset to other side
    float bVal = waveLine(u, v, 5.8, t * 0.95 + 1.8,     1.0, b, rayAngle);

    float average = max(max(rVal, gVal), bVal);
    float whitening = 0;
    whitening = smoothstep(.8, .9, average);
    vec3 rgb = vec3(rVal + whitening, gVal + whitening, bVal + whitening);

    return rgb;
}

// ── centre core ──────────────────────────────────────────────────────────────
// Bright white centre that all rays converge to.

vec3 centreGlow(float r, float b) {
    float coreR  = 0.08 + 0.01 * b;
    float core   = exp(-r * r / (coreR * coreR)) * 2.5;
    float halo   = exp(-r * r / (0.25 * 0.25))   * 0.3 * (0.5 + b);
    return vec3(1.0, 0.97, 0.93) * (core + halo);
}

// ── ray glow ──────────────────────────────────────────────────────────────────
// Adds a soft white underglow along each ray axis to make them
// readable even when RGB channels overlap.

float rayAxisGlow(vec2 p, float rayAngle, float b) {
    float cosA = cos(-rayAngle);
    float sinA = sin(-rayAngle);
    float u    = cosA * p.x - sinA * p.y;
    float v    = sinA * p.x + cosA * p.y;

    if (u < 0.0) return 0.0;

    float falloff  = exp(-u * u * 0.15) * exp(-u * 0.8);
    float lateral  = exp(-v * v / (0.002 + 0.002 * b) * 4);
    return falloff * lateral * 1.0;
}

// ── main ──────────────────────────────────────────────────────────────────────

void main() {
    vec2  p  = (uv * 2.0 - 1.0) * vec2(iRes.x / iRes.y, 1.0);
    float r  = length(p);
    float b  = bass();
    float m  = mid();

    // ray angles: right, up, left, down
    float angles[N_RAYS];
    angles[0] = 0.0;
    angles[1] = PI * 0.5;
    angles[2] = PI;
    angles[3] = PI * 1.5;

    vec3 col = vec3(0.0);

    // accumulate all four rays
    for (int i = 0; i < N_RAYS; i++) {
        col += rayColour(p, angles[i], b, m);
        // col += vec3(rayAxisGlow(p, angles[i], b) * rand(p + iTime*.001));
    }

    // add centre
    // col += centreGlow(r, b);

    // tone map
    // col       = col / (col + 0.9);
    // col       = pow(col, vec3(0.88));
    fragColor = vec4(col, iAlpha);
}