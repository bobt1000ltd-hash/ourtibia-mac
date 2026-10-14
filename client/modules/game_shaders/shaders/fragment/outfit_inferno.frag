// MyOTS outfit shader: Inferno - churning fire across the outfit with a burning rim (loyalty store).
const float offset = 1.0 / 64.0;
uniform float u_Time;
uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;

float hash(vec2 p)
{
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float noise(vec2 p)
{
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fire(vec2 uv)
{
    float n = noise(uv * 10.0 + vec2(0.0, u_Time * 3.0)) * 0.6;
    n += noise(uv * 22.0 + vec2(u_Time * 1.3, u_Time * 5.0)) * 0.4;
    return n;
}

vec3 fireColor(float n)
{
    vec3 c = mix(vec3(0.5, 0.0, 0.0), vec3(1.0, 0.35, 0.0), smoothstep(0.2, 0.55, n));
    return mix(c, vec3(1.0, 0.9, 0.3), smoothstep(0.55, 0.9, n));
}

void main()
{
    vec4 col = texture2D(u_Tex0, v_TexCoord);
    if (col.a < 0.5) {
        float a = texture2D(u_Tex0, v_TexCoord + vec2(offset, 0.0)).a +
                  texture2D(u_Tex0, v_TexCoord - vec2(offset, 0.0)).a +
                  texture2D(u_Tex0, v_TexCoord + vec2(0.0, offset)).a +
                  texture2D(u_Tex0, v_TexCoord - vec2(0.0, offset)).a;
        if (a > 0.0) {
            float n = fire(v_TexCoord);
            float glow = 0.35 + 0.5 * n;
            gl_FragColor = vec4(fireColor(n) * glow, glow);
            return;
        }
        if (col.a < 0.01)
            discard;
        gl_FragColor = col;
        return;
    }

    float lum = dot(col.rgb, vec3(0.299, 0.587, 0.114));
    float n = fire(v_TexCoord);
    vec3 flame = fireColor(n * 0.7 + lum * 0.4);
    vec3 rgb = mix(col.rgb, flame, 0.7);
    rgb *= 0.9 + 0.2 * sin(u_Time * 17.0) * sin(u_Time * 7.0);

    gl_FragColor = vec4(clamp(rgb, 0.0, 1.0), col.a);
}
