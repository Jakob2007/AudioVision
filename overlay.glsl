#version ${GLSL_VERSION}
${PRECISION}

uniform sampler2D iFFT;
uniform sampler2D iText;
uniform float iTime;
uniform float iAlpha;
uniform vec2 iRes;
in vec2 uv;
out vec4 fragColor;

#define N_BARS 32

float fft(float x){
    return texture(iFFT, vec2(x, 0.0)).r;
}

float bass(){
    float s = 0.0;
    for(int i = 0; i < 8; i++) s += fft(float(i) / 512.0);
    return s / 8.0;
}

void main(){
    vec2 p = (uv * 2.0 - 1.0) * vec2(iRes.x / iRes.y, 1.0);
    float b = bass();

    /* dark blurred background — just a deep vignette */
    float vign = 1.0 - smoothstep(0.3, 1.4, length(p));
    vec3 bg = vec3(0.04, 0.04, 0.08) * vign;

    /* subtle bass pulse ring behind the text */
    float r = length(p);
    float pulse = 0.6 + 0.4 * b;
    float ring = exp(-abs(r - pulse * 0.55) * 18.0) * 0.4 * b;
    bg += vec3(0.4, 0.2, 0.8) * ring;

    /* text texture — rendered by Pillow on CPU */
    vec4 textSample = texture(iText, uv);
    vec3 col = mix(bg, textSample.rgb, textSample.a);

    // vignette
    float vignette = smoothstep(1.60 - b*.2, 2.30 - b*.2, r);
    col = mix(col, vec3(0.15, 0.0, 0.15), vignette);

    /* fade the whole overlay with iAlpha */
    fragColor = vec4(col, iAlpha);
}