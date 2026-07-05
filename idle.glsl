#version ${GLSL_VERSION}
${PRECISION}
uniform float iTime;
uniform float iAlpha;
uniform vec2 iRes;
in vec2 uv;
out vec4 fragColor;

float g(vec4 p, float s) {
    return abs(dot(sin(p *= s), cos(p.zxwy)) - 1.) / s;
}

void main() {
    vec2 C = uv * iRes;
    vec2 r = iRes;

    float i = 0.0, d = 0.0, z = 0.0, s = 0.0;
    float T = iTime;
    vec4 o = vec4(0.0), q = vec4(0.0), p = vec4(0.0);
    vec4 U = vec4(2.0, 1.0, 0.0, 3.0);

    for (int n = 0; n < 78; n++) {
        i += 1.0;

        z += d + 5e-4;

        q = vec4(normalize(vec3(C - 0.5 * r, r.y)) * z, 0.2);
        q.z += T / 30.0;

        s = q.y + 0.1;
        q.y = abs(s);

        p = q;
        p.y -= 0.11;
        p.xy *= mat2(cos(11.0 * U.z - 2.0 * p.z),
                     cos(11.0 * U.y - 2.0 * p.z),
                     cos(11.0 * U.w - 2.0 * p.z),
                     cos(11.0 * U.z - 2.0 * p.z));
        p.y -= 0.2;

        d = abs(g(p, 8.0) - g(p, 24.0)) / 4.0;

        p = 1.0 + cos(0.7 * U + 5.0 * q.z);

        float denom = max(s > 0.0 ? d : d * d * d, 5e-4);
        o += (s > 0.0 ? 1.0 : 0.1) * p.w * p / denom;
    }

    o += (1.4 + sin(T) * sin(1.7 * T) * sin(2.3 * T))
         * 1e3 * U / length(q.xy);

    vec4 col = tanh(o / 1e5);
    fragColor = vec4(col.rgb, col.a * iAlpha);
}