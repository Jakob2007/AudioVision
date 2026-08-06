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
    return texture(iFFT, vec2(abs(x-.5)*.02, 0.0)).r * .15;
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

vec3 currentHue() {
    float hue = iTime * 0.04;
    return vec3(
        0.5 + 0.5 * sin(hue * TWO_PI),
        0.5 + 0.5 * sin(hue * TWO_PI + TWO_PI / 3.0),
        0.5 + 0.5 * sin(hue * TWO_PI + TWO_PI * 2.0 / 3.0)
    );
}

vec3 ringColour(float t) {
    float hue = iTime * 0.04;

    vec3 rgb1 = vec3(
        0.5 + 0.5 * sin(hue * TWO_PI),
        0.5 + 0.5 * sin(hue * TWO_PI + TWO_PI / 3.0),
        0.5 + 0.5 * sin(hue * TWO_PI + TWO_PI * 2.0 / 3.0)
    );

    vec3 rgb2 = vec3(
        0.5 + 0.5 * sin(hue * TWO_PI + PI),
        0.5 + 0.5 * sin(hue * TWO_PI + PI + TWO_PI / 3.0),
        0.5 + 0.5 * sin(hue * TWO_PI + PI + TWO_PI * 2.0 / 3.0)
    );

    // innermost rings: pure white
    // then transitions into shifting RGB, fading to white at the outer edge
    vec3 innerCol  = mix(rgb1, rgb2, t);
    float whiteT   = smoothstep(0.0, 0.75, t);
    vec3  outerCol = vec3(1.0);

    vec3 col = mix(innerCol, outerCol, whiteT);

    // force innermost band fully white
    col = mix(vec3(1.0), col, smoothstep(0.0, 0.12, t));

    return col;
}

// ── main ──────────────────────────────────────────────────────────────────────

void main() {
    vec2 ndc = (uv * 2.0 - 1.0) * vec2(iRes.x / iRes.y, 1.0);

    float orbitSpeed = 0.12;
    float camAngle   = iTime * orbitSpeed;
    float camHeight  = 5.0 + sin(iTime) * 0.7;
    float camDist    = 5.0 + cos(iTime * 0.5 - sin(iTime * 0.5) * 0.5);

    vec3 camPos  = vec3(sin(camAngle) * camDist *.5,
                        camHeight,
                        cos(camAngle) * camDist *.5);
    vec3 target  = vec3(0.0);
    vec3 forward = normalize(target - camPos);
    vec3 right   = normalize(cross(forward, vec3(0.0, 1.0, 0.0)));
    vec3 up      = cross(right, forward);
    vec3 rayDir  = normalize(forward + 1.1 * (ndc.x * right + ndc.y * up));

    // ── march ─────────────────────────────────────────────────────────────────
    float hitRing = -1.0;
    float hitNormR = 0.0;
    vec3  hitPos;

    float slabH = 0.50;
    float tEnter, tExit;
    if (slabTest(camPos, rayDir, slabH, tEnter, tExit)) {
        float t       = max(tEnter - 0.05, 0.0);
        float maxDist = min(tExit + 0.1, 18.0);

        for (int i = 0; i < 96; i++) {
            vec3  p   = camPos + t * rayDir;
            vec2  res = sceneSDF(p);
            float d   = res.x;

            if (d < 0.0008) {
                hitRing  = res.y;
                hitPos   = p;
                break;
            }
            if (t > maxDist) break;
            t += d * 0.85;
        }
    }

    // ── shade ─────────────────────────────────────────────────────────────────
    vec3 col = vec3(0.0);
    vec3 hue = currentHue();

    if (hitRing >= 0.0) {
        vec3  N        = calcNormal(hitPos);
        vec3  baseCol  = ringColour(hitRing);
        vec3  lightDir = normalize(-hitPos);
        float diff     = max(dot(N, lightDir), 0.0);

        // emission: innermost rings blast white
        float emit    = pow(1.0 - hitRing, 2.5) * 3.0;
        float diffuse = diff * (1.0 - hitRing * 0.8);

        col = baseCol * (emit + diffuse * 0.6);

        // RGB coloured rim light — comes from the direction of the inner ring
        // giving outer rings a coloured edge as if lit by the glowing centre
        float rim = pow(1.0 - abs(dot(N, normalize(camPos - hitPos))), 3.0);
        // inner rings: white rim. outer rings: RGB rim from the hue
        vec3 rimCol = mix(vec3(1.0), hue, smoothstep(0.0, 0.4, hitRing));
        col += rimCol * rim * 0.5 * (1.0 - hitRing * 0.6);

        // ── world-space RGB halo around the inner ring ────────────────────────
        // compute distance from hit point to the inner ring circle (radius = 1.0)
        // This creates a volumetric coloured glow that hugs the first ring
        // and illuminates nearby geometry in colour
        float hitR      = length(vec2(hitPos.x, hitPos.z));
        float innerRing = 1.0;                          // the innermost ring radius
        float distToInner = abs(hitR - innerRing);      // radial distance from inner ring

        // halo strength: bright close to inner ring, falls off over ~0.8 world units
        float haloStr  = exp(-distToInner * distToInner * 6.0);
        haloStr       *= exp(-hitPos.y * hitPos.y * 4.0);   // thin vertically
        haloStr       *= (1.0 - hitRing * 0.7);             // weaker on outer rings

        // hue channels shifted angularly so R/G/B land in different sectors
        float angle    = atan(hitPos.z, hitPos.x);
        float rShift   = 0.4;
        vec3 haloCol   = vec3(
            0.5 + 0.5 * sin(hue.r * TWO_PI + angle * 1.0 + rShift * 0.0),
            0.5 + 0.5 * sin(hue.g * TWO_PI + angle * 1.0 + rShift * 1.0),
            0.5 + 0.5 * sin(hue.b * TWO_PI + angle * 1.0 + rShift * 2.0)
        ) * haloStr * 1.2;

        col += haloCol;
    }

    // ── inner halo ────────────────────────────────────────────────────────────────
    float squash = max(abs(dot(forward, vec3(0.0,1.0,0.0))), 0.08);

    vec2 p = ndc;
    p.y /= squash;

    float radial = length(p);

    // radius of the glowing ring
    float haloRadius = 0.16;

    // thickness of the bright ring
    float haloWidth  = 0.035;

    // Gaussian ring: brightest at haloRadius
    float halo = exp(-pow((radial - haloRadius) / haloWidth, 2.0));

    // keep the very center darker
    float centerFade = smoothstep(0.0, haloRadius * 0.65, radial);
    halo *= centerFade;

    // coloured inner ring
    col += hue * halo * 2.8;

    // soft white bloom on top
    col += vec3(1.0) * halo * 1.6;

    // optional faint outer haze
    float haze = exp(-pow((radial - haloRadius) / 0.15, 2.0));
    col += hue * haze * 0.25;

    // ── tone map ──────────────────────────────────────────────────────────────
    col  = col / (col + 1.0);
    col  = pow(col, vec3(0.85));

    fragColor = vec4(col, iAlpha);
}