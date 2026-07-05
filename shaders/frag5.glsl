#version ${GLSL_VERSION}
${PRECISION}
uniform float iTime;
uniform float iAlpha;
uniform vec2 iRes;
uniform sampler2D iFFT;
in vec2 uv;
out vec4 fragColor;

#define PI 3.14159265

// ── FFT helpers ───────────────────────────────────────────────────────────────

float fft(float x) {
    return texture(iFFT, vec2(x, 0.0)).r;
}

// smoothed band averages to avoid jitter
float bass() {
    float s = 0.0;
    for (int i = 0; i < 6; i++) s += fft(float(i) / 512.0);
    return s / 6.0;
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

// ── palette ───────────────────────────────────────────────────────────────────

vec3 palette(float t) {
    vec3 a = vec3(0.5, 0.5, 0.5);
    vec3 b = vec3(0.5, 0.5, 0.5);
    vec3 c = vec3(1.0, 1.0, 1.0);
    vec3 d = vec3(0.1, 0.4, 0.5);
    return a + b * cos(2.0 * PI * (c * t + d));
}

// ── wave ──────────────────────────────────────────────────────────────────────

vec4 wave(vec2 p, float amp, float freq, float phase, float thick, vec3 hue) {
    float x = p.x - phase;
    float y = p.y + amp * sin(freq * x);
    float bright = smoothstep(0.0, 1.0, 1.0 - abs(y) / thick);
    return vec4(vec3(bright) * hue, 1.0);
}

// ── main ──────────────────────────────────────────────────────────────────────

void main() {
    vec2 p = (uv * 2.0 - 1.0) * vec2(iRes.x / iRes.y, 1.0);

    float b  = bass();
    float m  = mid();
    float tr = treble();

    // ── per-frame modifiers derived from FFT ──────────────────────────────────
    //
    //  Bass   → panning speed  — kick drums push the waves across faster,
    //           then they settle back. Most visceral connection to rhythm.
    //
    //  Mid    → inter-layer interference — raises the amplitude envelope of
    //           later (slower) layers so chords and voices create visible
    //           beating between wave trains without changing wave shape.
    //
    //  Treble → micro-distortion of the horizontal coordinate — a very small
    //           spatial wobble applied before the wave is evaluated, giving a
    //           subtle shimmer on hi-hats/cymbals. Kept tiny so it reads as
    //           texture, not noise.

    // bass: smooth the raw value slightly with a time-weighted sine so the
    // speed increase feels like inertia rather than an instant jump
    float speedBoost = 1.0 + 2.2 * b * (0.7 + 0.3 * sin(iTime * 0.8));

    // mid: scales how much adjacent layers interfere with each other
    float interference = 0.18 + 0.55 * m;

    // treble: tiny spatial distortion — applied to x before wave evaluation
    float shimmerAmp  = 0.004 + 0.018 * tr;
    float shimmerFreq = 12.0 + 8.0 * tr;
    float px = p.x + shimmerAmp * sin(shimmerFreq * p.x + iTime * 3.5);

    vec2 pd = vec2(px, p.y);

    vec4 col = vec4(0.0, 0.0, 0.0, 1.0);

    for (float layer = 0.0; layer < 1.0; layer += 0.1) {

        // base amplitude: unchanged slow breathing — preserves the calm wave feel
        float amp = 0.25 + 0.25 * sin(iTime * 0.9 + layer) * (1.0 - layer);

        // mid raises amplitude of deeper (slower) layers — creates visible
        // beating between wave trains when chords are present
        amp += interference * (1.0 - layer) * 0.15;

        float freq = 2.0;   // kept fixed — wave shape stays slow and readable

        // bass drives panning speed — the core rhythmic connection
        float phase = iTime * (1.0 - layer) * speedBoost;

        float thick = 0.01 + 0.001 * pow(abs(pd.x), 8.0);

        vec3 hue = palette(0.5 * pd.x + 1.0 * layer - 0.5 * iTime);

        col += wave(pd, amp, freq, phase, thick, hue);
    }

    fragColor = vec4(col.rgb, iAlpha);
}