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
#define TWO_PI PI * 2.0

vec3 circle_tf(vec2 pos, vec2 xy) {
    float size = .1;
    float thickness = .004;

    float a = atan(xy.x, xy.y);
    float s = PI / a;
    float amp = texture(iFFT, vec2(s, 0.0)).r * .1;

    float d = distance(pos, xy);
    float center_dist = abs(d-(size + amp));
    float val = 1 - smoothstep(thickness, thickness+.01, center_dist);

    vec3 col = vec3(0, 1, 1) * val;

    return col;
}

float fft(float x){
    return texture(iFFT, vec2(x, 0.0)).r;
}
float bass(){
    float s = 0.0;
    float c = 20;
    for(int i = 0; i < c; i++) s+= fft(i / 512.0) * (1/c);
    return max(pow(20, s *.5) -1.2, 0) * .3;
}

vec3 circle(float base_size, vec3 col, vec2 pos, vec2 xy, float dir) {
    float thickness = .006;

    float a = atan(xy.x - pos.x, xy.y - pos.y);
    float s = abs(a) / PI * .02;
    float amp = (texture(iFFT, vec2(s, 0.0)).r + texture(iFFT, vec2(s+.001, 0.0)).r) * .05 * dir;
    float size = base_size + pow(10, amp)-1;

    float d = distance(pos, xy);
    float ring_dist = abs(d - size);
    float val = 1 - smoothstep(thickness, thickness+.01, ring_dist);

    float inner = max(1 - (size - d) / amp, 0);

    if (inner < 1) {
        val+= inner * (1 + bass());
    }

    float funk = -min(1 - (size - d) / amp, 0);

    return col * val;
}

vec3 text() {
    float b = bass();

    vec2  center = vec2(0.5);   // Bezugspunkt für Skalierung

    float text_y = -.1;
    vec2 tuv = (vec2(uv.x, uv.y - text_y) - center)*(1-b*.2) + center;

    float shakeAmp = 0.0015;
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
    float radius = 0.006;
    for (int i = 0; i < N; i++) {
        float a = float(i) / float(N) * 6.2831853 + (mod(iTime * 113.5, 13.0)) / 79;
        vec2 o = vec2(cos(a), sin(a)) * radius;
        glow += texture(iText, tuv + o).a;
        glow += texture(iText, tuv + o * 0.5).a;
    }
    glow /= float(N) * 2.0;

    float pulse = 0.92 + 0.08 * sin(iTime * 2.0);

    vec3 col = vec3(0.0);
    vec3 bloomColor = vec3(0.6, 0.75, 1.0);
    col += bloomColor * glow * 0.8;
    col = mix(col, textCol * pulse, textA);

    return col;
}

vec3 snow()
{
    vec2 p = uv - 0.5;
    p.x *= iRes.x / iRes.y;

    if (length(p) < .2) {
        return vec3(0);
    }

    vec3 col = vec3(0.0);

    float b = bass();

    const float PARTICLES = 40.0;

    for (float i = 0.0; i < PARTICLES; i++)
    {
        float seed = i + 1;

        float angle =
            fract(sin(seed * 91.17) * 43758.5453)
            * 6.2831853;

        float randomRadius =
            fract(sin(seed * 17.13) * 15731.743);

        float speed = 0.08 + randomRadius * 0.04 + b * b * .001;

        float distance =
            fract(randomRadius + iTime * speed);

        float size =
            mix(
                0.003,
                0.009,
                fract(sin(seed * 43.71) * 951.17)
            );

        vec2 particlePos =
            vec2(cos(angle), sin(angle)) * distance;

        float d = length(p - particlePos);

        // Soft-edged circular particle.
        float particle =
            1.0 - smoothstep(size * 0.15, size, d);

        col += particle;
    }

    col = 1.0 - exp(-col * 1.5);

    return col;
}

// vec3 bg() {
//     vec2 uv = fragCoord.xy / iResolution.xy;
    
//     float o = texture(iChannel1, uv * 0.25 + vec2(0.0, iTime * 0.025)).r;
//     float d = (texture(iChannel0, uv * 0.25 - vec2(0.0, iTime * 0.02 + o * 0.02)).r * 2.0 - 1.0);
    
//     float v = uv.y + d * 0.1;
//     v = 1.0 - abs(v * 2.0 - 1.0);
//     v = pow(v, 2.0 + sin((iTime * 0.2 + d * 0.25) * TAU) * 0.5);
    
//     vec3 color = vec3(0.0);
    
//     float x = (1.0 - uv.x * 0.75);
//     float y = 1.0 - abs(uv.y * 2.0 - 1.0);
//     color += vec3(x * 0.5, y, x) * v;
    
//     vec2 seed = fragCoord.xy;
//     vec2 r;
//     r.x = fract(sin((seed.x * 12.9898) + (seed.y * 78.2330)) * 43758.5453);
//     r.y = fract(sin((seed.x * 53.7842) + (seed.y * 47.5134)) * 43758.5453);

//     float s = mix(r.x, (sin((iTime * 2.5 + 60.0) * r.y) * 0.5 + 0.5) * ((r.y * r.y) * (r.y * r.y)), 0.04); 
//     color += pow(s, 70.0) * (1.0 - v);
    
//     fragColor.rgb = color;
//     fragColor.a = 1.0;
// }


void main() {
    vec2 xy = uv;
    xy.x *= iRes.x / iRes.y;

    vec2 pos = vec2(iRes.x / iRes.y * .5, .5);

    vec3 col = vec3(0);
    col+= circle(.1, vec3(1, 1, 1), pos, xy, .3);
    col+= circle(.15, vec3(.5, 1, 1), pos, xy, .8);
    col+= circle(.2, vec3(0, 1, 1), pos, xy, 1.2);
    
    // col+= circle(.4, vec3(1, 0, 1), pos, xy, 2) * bass();
    // col+= circle(.6, vec3(1, 0, 1), pos, xy, 2) * bass() * 1.2;
    // col+= circle(.8, vec3(1, 0, 1), pos, xy, 2) * bass() * 1.4;

    col+= vec3(1) * bass() * bass();

    col+= snow();

    col += text();

    fragColor = vec4(col, iAlpha);
}
