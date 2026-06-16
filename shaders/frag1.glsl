#version {glsl_version}
{precision}
uniform sampler2D iFFT;
uniform float iTime;
uniform float iBPM;
in vec2 uv;
out vec4 fragColor;

void main() {{
    float freq = texture(iFFT, vec2(uv.x, 0.0)).r;
    float beat = abs(sin(iTime * iBPM / 60.0 * 3.14159));
    float bar = step(uv.y, freq * (0.8 + 0.2 * beat));
    vec3 col = mix(vec3(0.1, 0.4, 0.8), vec3(1.0, 0.2, 0.4), uv.x);
    fragColor = vec4(col * bar, 1.0);
}}