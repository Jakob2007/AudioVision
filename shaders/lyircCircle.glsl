#version ${GLSL_VERSION}
${PRECISION}

uniform sampler2D iFFT;
uniform sampler2D iText;
uniform float iTime;
uniform float iBPM;
uniform vec2 iRes;
uniform float iAlpha;
in vec2 uv;
out vec4 fragColor;

#define N_BARS 32

float fft(float x){
    return texture(iFFT, vec2(x, 0.0)).r;
}

float bass(){
    float s = 0.0;
    for(int i = 0; i < 4; i++) s += fft(float(i) / 512.0);
    return s / 8.0;
}

void main(){
    vec2 p = (uv * 2.0 - 1.0) * vec2(iRes.x / iRes.y, 1.0);
    float r = length(p);
    float a = atan(p.y, p.x);
    float b = bass();

    /* ── deformed circle ─────────────────────────────────────────── */
    float wave = 0.0;
    wave += 0.07 * sin(3.0 * a + iTime * 1.2) * b * 2;
    wave += 0.05 * sin(5.0 * a - iTime * 0.8) * b;
    wave += 0.03 * sin(8.0 * a + iTime * 2.1) * (b * 0.5 + 0.3);
    wave += 0.02 * sin(13.0 * a - iTime * 1.7) * b;

    float circleR = 0.48 + wave;
    float dist    = r - circleR;
    float thick   = 0.012 + 0.018 * b * b + abs(wave * 0.3);
    float ring    = 1.0 - smoothstep(0.0, thick, abs(dist));
    float fill    = smoothstep(circleR + thick, circleR * 0.01, r) * 0.05 * b;

    float shimmer = sin(a * 4.0 - iTime * 1.5) * 0.5 + 0.5;
    vec3 colA     = vec3(0.20, 0.50, 0.90);
    vec3 colB     = vec3(9.00, 0.00, 0.30);
    vec3 circCol  = mix(colA, colB, shimmer) * (ring + fill);

    /* ── composite ───────────────────────────────────────────────── */
    vec3 col = circCol;

    /* ── bloom ───────────────────────────────────────────────────── */
    col += mix(colA, colB, shimmer) * exp(-abs(dist) * 40.0) * 0.55 * (b * 0.5 + 0.5);

    /* ── vignette + tone map ─────────────────────────────────────── */
    col *= 1.0 - smoothstep(0.90, 1.60, r);
    // col  = col / (col + 0.8);
    col  = pow(col, vec3(0.85));

    /* overlay texture — rendered by Pillow on CPU */
    // ---- Parameter ----
    vec2  center = vec2(0.5);   // Bezugspunkt für Skalierung
    // float b  = ...;          // Ihr Größenparameter: b > 1 vergrößert, b < 1 verkleinert

    // ---- 1. Skalierung um den Mittelpunkt (Parameter b) ----
    vec2 tuv = (uv - center)*(1-b*.2) + center;

    // ---- 2. Dezentes Zittern (Shake) ----
    float shakeAmp = 0.0025;    // bewusst klein gehalten, um die Lesbarkeit zu wahren
    vec2 shake = vec2(
        sin(iTime * 26.0) + sin(iTime * 14.6),
        cos(iTime * 22.0) + sin(iTime * 10.2)
    ) * shakeAmp;
    tuv += shake*b;

    // ---- 3. Chromatische Aberration (atmosphärischer Farbversatz) ----
    float aberr = 0.05 * b * b;
    vec4 tR = texture(iText, tuv + vec2(aberr, 0.0));
    vec4 tG = texture(iText, tuv);
    vec4 tB = texture(iText, tuv - vec2(aberr, 0.0));
    vec3 textCol = vec3(tR.r, tG.g, tB.b);
    float textA  = max(max(tR.a, tG.a), tB.a);

    // ---- 4. Bloom / Leuchtkranz ----
    float glow = 0.0;
    const int N = 12;
    float radius = 0.006;
    for (int i = 0; i < N; i++) {
        float a = float(i) / float(N) * 6.2831853;
        vec2 o = vec2(cos(a), sin(a)) * radius;
        glow += texture(iText, tuv + o).a;         // äußerer Ring
        glow += texture(iText, tuv + o * 0.5).a;   // innerer Ring
    }
    glow /= float(N) * 2.0;

    // ---- 5. Atmosphärisches Pulsieren ----
    float pulse = 0.92 + 0.08 * sin(iTime * 2.0);

    // ---- 6. Komposition ----
    vec3 bloomColor = vec3(0.6, 0.75, 1.0);        // z. B. kühles Leuchten
    col += bloomColor * glow * 0.8;                // Halo liegt hinter dem Text
    col = mix(col, textCol * pulse, textA);        // Text darüber, bleibt lesbar

    fragColor = vec4(col, iAlpha);
}