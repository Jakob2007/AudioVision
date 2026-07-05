#version ${GLSL_VERSION}
${PRECISION}

uniform sampler2D iFFT;
uniform float iTime;
uniform float iBPM;
uniform vec2 iRes;
uniform float iAlpha;
in vec2 uv;
out vec4 fragColor;


#define N_BARS 16

float fft(float x){
    return texture(iFFT, vec2(x, 0.0)).r;
}

float bass(){
    float s = 0.0;
    for(int i = 0; i < 8; i++) s += fft(float(i) / 512.0);
    return s / 8.0;
}

float mid(int bin){
    float lo = 0.05, hi = 0.55;
    float x = lo + (hi - lo) * (float(bin) + 0.5) / float(N_BARS);
    return fft(x);
}

void main(){
    vec2 p = (uv * 2.0 - 1.0) * vec2(iRes.x / iRes.y, 1.0);
    float r = length(p);
    float a = atan(p.y, p.x);
    float b = bass();

    /* ── bar chart ───────────────────────────────────────────────── */
    vec3 barCol = vec3(0.0);
    float BAR_W   = 0.085;
    float BAR_GAP = 0.020;
    float TOTAL   = BAR_W + BAR_GAP;
    float half_N    = float(N_BARS) * 0.5;

    for(int i = 0; i < N_BARS; i++){
        float xi  = (float(i) - half_N + 0.5) * TOTAL;
        float bh  = mid(i) * 0.85;
        float inX = step(abs(p.x - xi), BAR_W * 0.5);
        float inY = step(abs(p.y), bh);
        if(inX * inY > 0.0){
            float norm = abs(p.y) / bh;
            vec3 lo = vec3(0.05, 0.30, 0.90);
            vec3 hi = vec3(0.00, 0.90, 0.80);
            barCol  = mix(lo, hi, norm);
            barCol *= 1.0 - smoothstep(0.82, 1.0, norm);
        }
    }

    /* ── deformed circle ─────────────────────────────────────────── */
    float wave = 0.0;
    wave += 0.07 * sin(3.0 * a + iTime * 1.2) * b;
    wave += 0.05 * sin(5.0 * a - iTime * 0.8) * b;
    wave += 0.03 * sin(8.0 * a + iTime * 2.1) * (b * 0.5 + 0.3);
    wave += 0.02 * sin(13.0 * a - iTime * 1.7) * b;

    float circleR = 0.38 + wave;
    float dist    = r - circleR;
    float thick   = 0.012 + 0.018 * b;
    float ring    = 1.0 - smoothstep(0.0, thick, abs(dist));
    float fill    = smoothstep(circleR + thick, circleR * 0.2, r) * 0.12 * b;

    float shimmer = sin(a * 4.0 - iTime * 2.5) * 0.5 + 0.5;
    vec3 colA     = vec3(0.95, 0.35, 0.60);
    vec3 colB     = vec3(1.00, 0.70, 0.20);
    vec3 circCol  = mix(colA, colB, shimmer) * (ring + fill);

    /* ── composite ───────────────────────────────────────────────── */
    vec3 col = barCol + circCol;

    /* ── bloom ───────────────────────────────────────────────────── */
    col += mix(colA, colB, shimmer) * exp(-abs(dist) * 18.0) * 0.55 * (b * 0.5 + 0.5);

    for(int i = 0; i < N_BARS; i++){
        float xi = (float(i) - half_N + 0.5) * TOTAL;
        float bh = mid(i) * 0.85;
        float dx = max(abs(p.x - xi) - BAR_W * 0.5, 0.0);
        float dy = max(abs(p.y) - bh, 0.0);
        float bd = length(vec2(dx, dy));
        float fi = float(i) / float(N_BARS);
        col += mix(vec3(0.05, 0.30, 0.90), vec3(0.00, 0.90, 0.80), fi) * exp(-bd * 22.0) * 0.22;
    }

    /* ── vignette + tone map ─────────────────────────────────────── */
    col *= 1.0 - smoothstep(0.65, 1.45, r);
    col  = col / (col + 0.8);
    col  = pow(col, vec3(0.85));

    fragColor = vec4(col, iAlpha);
}