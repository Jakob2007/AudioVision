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

#define PI     3.14159265

float fftAt(float x) {
    return texture(iFFT, vec2(clamp(x, 0.0, 1.0), 0.0)).r;
}

float bass() {
    float s = 0.0;
    for (int i = 0; i < 6; i++) s += fftAt(float(i) / 512.0);
    return pow(10, s / 6.0)-1;
}

vec3 text() {
    float b = bass();

    vec2  center = vec2(0.5);   // Bezugspunkt für Skalierung

    float text_y = .2;
    vec2 tuv = (vec2(uv.x, uv.y - text_y) - center)*(1-b*.2) + center;

    float shakeAmp = 0.005;
    vec2 shake = vec2(
        sin(iTime * 26.0) + sin(iTime * 14.6),
        cos(iTime * 22.0) + sin(iTime * 10.2)
    ) * shakeAmp;
    tuv += shake * b;

    float aberr = 0.5 * b * b;
    vec4 tR = texture(iText, tuv + vec2(aberr, 0.0));
    vec4 tG = texture(iText, tuv);
    vec4 tB = texture(iText, tuv - vec2(aberr, 0.0));
    vec3 textCol = vec3(tR.r, tG.g, tB.b);
    float textA = max(max(tR.a, tG.a), tB.a);

    float glow = 0.0;
    const int N = 6;
    float radius = 0.06;
    for (int i = 0; i < N; i++) {
        float a = float(i) / float(N) * 6.2831853 + (mod(iTime * 113.5, 13.0)) / 79;
        vec2 o = vec2(cos(a), sin(a)) * radius;
        glow += texture(iText, tuv + o).a;
        glow += texture(iText, tuv + o * 0.5).a;
    }
    glow*= b * b * 200 / float(N);

    float pulse = 0.92 + 0.08 * sin(iTime * 2.0);

    vec2 suv = (tuv + vec2(iTime * .2, -0.1)) * 3;
    vec3 big_col = texture(iText, suv).rgb;

    vec3 col = vec3(0.0);
    vec3 bloomColor = vec3(0.6, 0.75, 1.0);
    col += bloomColor * glow * 0.8;
    col+= big_col;
    col = mix(col, textCol * pulse, textA);

    return col;
}

void main() {
    vec3 col = vec3(0);
    // col+= vec3(1, 1, 1) * bass();

    col += text();

    fragColor = vec4(col, iAlpha);
}
