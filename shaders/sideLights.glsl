#version ${GLSL_VERSION}
${PRECISION}

uniform sampler2D iFFT;
uniform float iTime;
uniform float iBPM;
uniform float iAlpha;
in vec2 uv;
out vec4 fragColor;

const float PI = 3.14159265359;

float fft(float x){
    return texture(iFFT, vec2(x, 0.0)).r;
}

float bass(){
    float s = 0.0;
    for(int i = 0; i < 10; i++) s += fft(float(i) / 512.0);
    return s * 10;
}

float audioBars(vec2 uv, float volume)
{
    float barWidth = 0.1 + (-.02 * bass());
    float fadeWidth = 0.035;

    float height = 1;

    // Bars anchored to the outer edges
    float leftBar  = 1.0 - smoothstep(0.0, barWidth, uv.x);
    float rightBar = smoothstep(1.0 - barWidth, 1.0, uv.x);

    // Fade toward the center-facing edges
    float leftFade  = 1.0 - smoothstep(barWidth - fadeWidth, barWidth, uv.x);
    float rightFade = smoothstep(1.0 - barWidth, 1.0 - barWidth + fadeWidth, uv.x);

    // Vertical mask: bars grow upward from the bottom
    float vertical = 1.0 - smoothstep(height - 0.003, height, uv.y);

    float bars = max(leftBar * leftFade, rightBar * rightFade);

    return bars * vertical;
}

vec3 circle(vec2 uv, float bassLevel, float time) {
    vec2 p = uv - 0.5;
    float r = length(p);
    float a = atan(p.y, p.x);
    float fromTop = abs(mod(a - PI * 0.5 + PI, 2.0 * PI) - PI);
    float wave = fft(fromTop / PI) * 0.1;

    float circleR = 0.38 + wave + bassLevel * 0.;
    float dist    = r - circleR;
    float thick   = 0.1 + bassLevel * bassLevel * 0.0 + abs(wave * 0.3) * 20;
    float ring    = 1.0 - smoothstep(0.0, thick, abs(dist));
    float fill    = 0.1 * bassLevel * bassLevel;

    float shimmer = sin(fromTop * 4.0 - time * 3.0) * 0.5 + 0.5;

    vec3 colA = vec3(0.20, 0.50, 0.90);
    vec3 colB = vec3(9.00, 0.00, 0.30);
    return mix(colA, colB, shimmer) * (ring + fill);
}

void main() {
    float b = bass();
    float whiteMix = smoothstep(1.0, 1.5, b);
    vec3 color = mix(vec3(0.20, 0.50, 0.90), vec3(1.0), whiteMix);
    
    vec3 col  = pow(color, vec3(0.85));
    col += smoothstep(0.0, 1.5, ) * vec3(1, 0, .2) * .2;
    
    col += circle(uv, b, iTime);
    fragColor = vec4(col, iAlpha);
}