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
#define PI 3.14159265

float fft(float x){
    return texture(iFFT, vec2(x, 0.0)).r;
}

float bass(float scalar){
    float lo = 0.00, hi = 0.02;
    float x = lo + (hi - lo) * (scalar);
    return fft(x);
}

float bass_av(){
    float s = 0.0;
    for(int i = 0; i < 4; i++) s += fft(float(i) / 512.0);
    return s / 8.0;
}

float mid(int bin){
    float lo = 0.00, hi = 0.04;
    float x = lo + (hi - lo) * (float(bin) + 0.5) / float(N_BARS);
    return fft(x);
}

void main(){
    vec2 p = (uv * 2.0 - 1.0) * vec2(iRes.x / iRes.y, 1.0);
    float r = length(p);
    float a = atan(p.y, p.x);
    float b = bass_av();

    /* ── bar chart ───────────────────────────────────────────────── */
    vec3 barCol = vec3(0.0);

    float totalWidth = 1.5;               // full screen in X (NDC)
    float gapRatio   = 0.20;              // gap = 25% of bar width

    float BAR_W = totalWidth / (float(N_BARS) + gapRatio * float(N_BARS - 1));
    float BAR_GAP = BAR_W * gapRatio;
    float TOTAL = BAR_W + BAR_GAP;
    float MAX_BAR_HEIGHT = 0.5;

    for(int i = 0; i < N_BARS; i++){
        // left bar
        float xiL = (float(i) - N_BARS + 0.5) * TOTAL;
        float bhL  = mid(i) * MAX_BAR_HEIGHT * (1 - float(i) / N_BARS);
        float inXL = step(abs(p.x - xiL), BAR_W * 0.5);
        float inYL = step(abs(p.y), bhL);
        if(inXL * inYL > 0.0){
            float norm = abs(p.y) / bhL;
            vec3 lo = vec3(0.05, 0.30, 0.90);
            vec3 hi = vec3(0.00, 0.90, 0.80);
            barCol  = mix(lo, hi, norm);
            barCol *= 1.0 - smoothstep(0.91, 1.0, norm);
        }

        // right bar (mirrored)
        float xiR  = ((N_BARS - float(i)) - 0.5) * TOTAL;
        float bhR  = bhL; // same height calculation
        float inXR = step(abs(p.x - xiR), BAR_W * 0.5);
        float inYR = step(abs(p.y), bhR);
        if(inXR * inYR > 0.0){
            float norm = abs(p.y) / bhR;
            vec3 lo = vec3(0.05, 0.30, 0.90);
            vec3 hi = vec3(0.00, 0.90, 0.80);
            barCol  = mix(lo, hi, norm);
            barCol *= 1.0 - smoothstep(0.90, 1.0, norm);
        }
    }

    /* ── deformed circle ─────────────────────────────────────────── */
    float fromTop = abs(mod(a - PI * 0.5 + PI, 2.0 * PI) - PI);
    float wave = bass(fromTop / PI) * .1;

    float circleR = 0.38 + wave + b*.5;
    float dist    = r - circleR;
    float thick   = 0.012 + 0.018 * b * b * 20 + abs(wave * 0.3);
    float ring    = 1.0 - smoothstep(0.0, thick, abs(dist));
    // float fill    = smoothstep(circleR + thick, circleR * 0.01, r) * 0.05 * b;
    float fill    = 0.05 * b;

    float shimmer;
    shimmer = sin(fromTop * 4.0 - iTime * 3.0) * 0.5 + 0.5;

    vec3 colA     = vec3(0.20, 0.50, 0.90);
    vec3 colB     = vec3(9.00, 0.00, 0.30);
    vec3 circCol  = mix(colA, colB, shimmer) * (ring + fill);

    /* ── composite ───────────────────────────────────────────────── */
    vec3 col = barCol + circCol;

    /* ── bloom ───────────────────────────────────────────────────── */
    col += mix(colA, colB, shimmer) * exp(-abs(dist) * 40.0) * 0.55 * (b * 0.5 + 0.5);

    // bloom matching the left/right mirrored bar layout (use distinct names)
    float totalWidth2 = 1.5;               // full screen in X (NDC)
    float gapRatio2   = 0.20;              // gap = 20% of bar width
    float BAR_W2 = totalWidth2 / (float(N_BARS) + gapRatio2 * float(N_BARS - 1));
    float BAR_GAP2 = BAR_W2 * gapRatio2;
    float TOTAL2 = BAR_W2 + BAR_GAP2;
    float half_N = float(N_BARS) * 0.5;

    for(int i = 0; i < N_BARS; i++){
        // left bar position
        float xiL = (float(i) - float(N_BARS) + 0.5) * TOTAL2;
        float bhL = mid(i) * MAX_BAR_HEIGHT * (1.0 - float(i) / float(N_BARS));
        float dxL = max(abs(p.x - xiL) - BAR_W2 * 0.5, 0.0);
        float dyL = max(abs(p.y) - bhL, 0.0);
        float bdL = length(vec2(dxL, dyL));
        float fi = float(i) / float(N_BARS);
        col += mix(vec3(0.05, 0.30, 0.90), vec3(0.00, 0.90, 0.80), fi) * exp(-bdL * 26.0) * 0.18;

        // right (mirrored) bar position
        float xiR = ((float(N_BARS) - float(i)) - 0.5) * TOTAL2;
        float bhR = bhL;
        float dxR = max(abs(p.x - xiR) - BAR_W2 * 0.5, 0.0);
        float dyR = max(abs(p.y) - bhR, 0.0);
        float bdR = length(vec2(dxR, dyR));
        col += mix(vec3(0.05, 0.30, 0.90), vec3(0.00, 0.90, 0.80), fi) * exp(-bdR * 26.0) * 0.18;
    }

    /* ── vignette + tone map ─────────────────────────────────────── */
    col *= 1.0 - smoothstep(0.90, 1.60, r);
    // col  = col / (col + 0.8);
    col  = pow(col, vec3(0.85));

    fragColor = vec4(col, iAlpha);
}