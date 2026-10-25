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
#define N_RINGS 14
#define FFT_MAX 5

// ── FFT ──────────────────────────────────────────────────────────────────────

float fftAt(float x) {
    return texture(iFFT, vec2(abs(x-.5)*.02, 0.0)).r * 1.95;
    //return texture(iFFT, vec2(clamp((sin(x*TWO_PI*2)*.5+.5)*FFT_MAX + .0, 0.0, 1.0), 0.0)).r;
}
// float fftAt(float x) {
    
//     float pos = (sin(x * TWO_PI * 2.0) * 0.5 + 0.5) * FFT_MAX;

//     float i = floor(pos);
//     float t = fract(pos);

//     float u0 = clamp(i / FFT_MAX, 0.0, 1.0);
//     float u1 = clamp((i + 1.0) / FFT_MAX, 0.0, 1.0);

//     float fft0 = texture(iFFT, vec2(u0, 0.0)).r;
//     float fft1 = texture(iFFT, vec2(u1, 0.0)).r;

//     return mix(fft0, fft1, t) * .15;
// }

// ── ring geometry ─────────────────────────────────────────────────────────────
//
//  Each ring lives in the XZ-plane, centred at origin.
//  The FFT displaces it in Y, amplitude grows with radius.
//  We evaluate the SDF for a single torus cross-section analytically.
//
//  p        : query point in world space
//  radius   : ring centre radius
//  thickness: tube radius
//  fftAmp   : vertical displacement amplitude at this radius

float sdRing(vec3 p, float radius, float thickness, float fftAmp) {
    // sample FFT at angle around ring — makes the deformation angular
    float angle  = atan(p.z, p.x);                  // −PI..PI
    float t      = angle / TWO_PI + 0.5;             // 0..1
    float disp   = fftAt(t) * fftAmp;         // angular FFT sample

    // project point onto XZ plane to get distance from ring centre circle
    float dXZ    = length(vec2(p.x, p.z)) - radius;

    // torus SDF: distance to tube surface, with Y offset by FFT
    return length(vec2(dXZ, p.y - disp)) - thickness;
}

bool slabTest(vec3 ro, vec3 rd, float slabH,
              out float tEnter, out float tExit) {
    if (abs(rd.y) < 0.0001) {
        tEnter = 0.0; tExit = 1e10;
        return abs(ro.y) < slabH;
    }
    float t0 = (-slabH - ro.y) / rd.y;
    float t1 = ( slabH - ro.y) / rd.y;
    tEnter   = min(t0, t1);
    tExit    = max(t0, t1);
    return tExit > 0.0 && tEnter < 1e10;
}

// ── scene SDF ────────────────────────────────────────────────────────────────
//
//  Returns vec2(distance, ring_index_normalised 0..1)

vec2 sceneSDF(vec3 p) {
    float minD    = 1e10;
    float minRing = 0.0;

    float speed    = 0.18;         // rings move outward at this world-units/sec
    float maxR     = 3.2;          // maximum ring radius before it vanishes
    float thickness = 0.024;       // tube thickness — close but not touching
    float spacing  = maxR / float(N_RINGS);

    for (int i = 0; i < N_RINGS; i++) {
        // baseg offset stagers rings evenly
        float base   = float(i) * spacing;
        // fract() recycles the ring: once it hits maxR it reappears at 0
        // map ring radii into the range [1.0 .. maxR] so the innermost ring is at 1.0
        float radius01 = clamp(fract((base + iTime * speed) / maxR), spacing*.25, 1.0); // 0..1
        float radius   = 1.0 + radius01 * (maxR - 1.0);

        // FFT amplitude grows linearly with radius — outer rings react more
        // float fftAmp = radius * 2.00 * fftAt((radius - 1.0) / (maxR - 1.0) * 0.7);
        float fftAmp = radius * 0.50 + sin(radius*5 + iTime)+1;

        float d = sdRing(p, radius + 0.01, thickness, fftAmp);

        if (d < minD) {
            minD    = d;
            // normalise so 0 -> inner (radius==1.0), 1 -> outer (radius==maxR)
            minRing = (radius - 1.0) / (maxR - 1.0);
        }
    }

    return vec2(minD, minRing);
}

// ── normal ────────────────────────────────────────────────────────────────────

vec3 calcNormal(vec3 p) {
    float e = 0.001;
    return normalize(vec3(
        sceneSDF(p + vec3(e,0,0)).x - sceneSDF(p - vec3(e,0,0)).x,
        sceneSDF(p + vec3(0,e,0)).x - sceneSDF(p - vec3(0,e,0)).x,
        sceneSDF(p + vec3(0,0,e)).x - sceneSDF(p - vec3(0,0,e)).x
    ));
}

// ── colour ────────────────────────────────────────────────────────────────────
//
//  Inner rings (t≈0): white-orange hot glow
//  Outer rings (t≈1): deep blue, almost dark

vec3 ringColour(float t) {
    vec3 inner = vec3(1.00, 0.90, 0.70);   // warm white
    vec3 mid   = vec3(0.90, 0.40, 0.15);   // orange
    vec3 outer = vec3(0.05, 0.10, 0.35);   // dark blue
    if (t < 0.3)
        return mix(inner, mid,   (t-.05) / 0.3);
    return     mix(mid,  outer, (t - 0.3) / 0.7);
}

// ── ray march ────────────────────────────────────────────────────────────────

void main() {
    vec2 ndc = (uv * 2.0 - 1.0) * vec2(iRes.x / iRes.y, 1.0);

    // ── camera orbit ─────────────────────────────────────────────────────────
    float orbitSpeed = 0.12;
    float camAngle   = iTime * orbitSpeed;
    float camHeight  = 3.0 + sin(iTime) * 0.7;
    float camDist    = 5.0 + cos(iTime * 0.5 - sin(iTime * 0.5)*.5);

    vec3 camPos    = vec3(sin(camAngle) * camDist,
                          camHeight,
                          cos(camAngle) * camDist);
    vec3 target    = vec3(0.0, 0.0, 0.0);

    // camera basis
    vec3 forward   = normalize(target - camPos);
    vec3 right     = normalize(cross(forward, vec3(0.0, 1.0, 0.0)));
    vec3 up        = cross(right, forward);

    float fov      = 1.1;   // radians
    vec3 rayDir    = normalize(forward + fov * (ndc.x * right + ndc.y * up));

    // ── march ─────────────────────────────────────────────────────────────────
    float hitRing  = -1.0;
    vec3  hitPos;

    float slabH = 1.20;
    float tEnter, tExit;
    if (slabTest(camPos, rayDir, slabH, tEnter, tExit)) {
        float t         = max(tEnter - 0.05, 0.0);
        float maxDist = min(tExit + 0.1, 18.0);
        int   maxSteps = 96;

        for (int i = 0; i < maxSteps; i++) {
            vec3  p    = camPos + t * rayDir;
            vec2  res  = sceneSDF(p);
            float d    = res.x;

            if (d < 0.0008) {
                hitRing = res.y;
                hitPos  = p;
                break;
            }
            if (t > maxDist) break;

            // step conservatively — many thin close rings need care
            t += d * 0.85;
        }
    }

    // ── shade ─────────────────────────────────────────────────────────────────
    vec3 col = vec3(0.0);

    if (hitRing >= 0.0) {
        vec3  N        = calcNormal(hitPos);
        vec3  baseCol  = ringColour(hitRing);

        // light comes from the centre (world origin)
        vec3  lightDir = normalize(-hitPos);
        float diff     = max(dot(N, lightDir), 0.0);

        // inner rings: strong self-emission, outer rings: dimmer diffuse
        float emit     = pow(1.0 - hitRing, 2.5) * 2.2;   // bright core
        float diffuse  = diff * (1.0 - hitRing * 0.8);     // fades outward

        col = baseCol * (emit + diffuse * 0.6);

        // soft rim — outer edge of each tube catches a hint of light
        float rim = pow(1.0 - abs(dot(N, normalize(camPos - hitPos))), 3.0);
        col      += baseCol * rim * 0.3 * (1.0 - hitRing);
    }

    // ── atmospheric glow from centre ──────────────────────────────────────────
    // a faint radial haze even where no ring is hit
    float radial = length(ndc);
    float glow   = 0.04 / (radial * radial + 0.15);
    col         += vec3(1.0, 0.6, 0.3) * glow * (fftAt(0.02) * 0.3 + .7);

    // ── tone map + gamma ──────────────────────────────────────────────────────
    col  = col / (col + 1.0);
    col  = pow(col, vec3(0.85));

    fragColor = vec4(col, iAlpha);
}