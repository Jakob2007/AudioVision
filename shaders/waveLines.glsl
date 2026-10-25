#version ${GLSL_VERSION}
${PRECISION}
uniform float iTime;
uniform float iAlpha;
uniform vec2 iRes;
uniform sampler2D iFFT;
in vec2 uv;
out vec4 fragColor;

#define PI 3.14159265

float fft(float x) {
    return texture(iFFT, vec2(x, 0.0)).r;
}

float bass() {
    float s = 0.0;
    for (int i = 0; i < 3; i++) s += fft(float(i) / 512.0);
    return s / 3.0 * 10;
}

float mid() {
    float s = 0.0;
    for (int i = 0; i < 8; i++) s += fft(0.08 + float(i) / 160.0);
    return s / 8.0;
}

float treble() {
    float s = 0.0;
    for (int i = 0; i < 6; i++) s += fft(0.45 + float(i) / 160.0);
    return s / 6.0;
}

vec3 palette(float t) {
    vec3 a = vec3(0.5, 0.5, 0.5);
    vec3 b = vec3(0.5, 0.5, 0.5);
    vec3 c = vec3(1.0, 1.0, 1.0);
    vec3 d = vec3(0.1, 0.4, 0.5);
    return a + b * cos(2.0 * PI * (c * t + d));
}

vec4 wave(vec2 p, float amp, float freq, float phase, float thick, vec3 hue) {
    float x = p.x - phase;
    float y = p.y + amp * sin(freq * x) + sin(freq * x * 20 + iTime * 20) * bass() * .1;
    float bright = smoothstep(0.0, 1.0, 1.0 - abs(y) / thick);
    return vec4(vec3(bright) * hue, 1.0);
}

void main() {
    vec2 p = (uv * 2.0 - 1.0) * vec2(iRes.x / iRes.y, 1.0);

    float b  = bass();
    float m  = mid();
    float tr = treble();

    // bass: very slight speed nudge — waves drift a touch faster on kicks
    // kept small so the panning character of the original is fully preserved
    float speedMod = 1.0 + 0.00012 * b;

    // treble: sub-pixel horizontal shimmer — readable as texture, not jitter
    float shimmer = 0.006 * tr * sin(18.0 * p.x + iTime * 4.0);
    vec2 pd = vec2(p.x + shimmer, p.y);

    vec4 col = vec4(0.0, 0.0, 0.0, 1.0);

    for (float layer = 0.0; layer < 1.0; layer += 0.1) {

        // original amp — only bass adds a whisper of extra breath
        float amp = 0.25 + 0.25 * sin(iTime + layer) * (1.0 - layer)
                  + 0.4 * b * (1.0 - layer);

        float freq = 2.0;   // untouched — preserves the slow wave character

        // bass nudges scroll speed; each layer retains its own depth offset
        float phase = iTime * (1.0 - layer) * speedMod;

        // mid very slightly thickens lines — barely perceptible, adds warmth
        float thick = 0.01 + 0.001 * pow(abs(pd.x), 8.0)
                    + .5 * b * layer;

        // mid shifts the palette offset slightly — a slow hue breathe
        float hueT = 0.5 * pd.x + 1.0 * layer - 0.5 * iTime + 0.08 * m;
        vec3 hue = palette(hueT);

        col += wave(pd, amp, freq, phase, thick, hue) * (1 - layer);
    }

    fragColor = vec4(col.rgb, iAlpha);
}