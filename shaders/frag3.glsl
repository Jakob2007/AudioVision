#version ${GLSL_VERSION}
${PRECISION}

uniform sampler2D iFFT;
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

    fragColor = vec4(col, iAlpha);
}