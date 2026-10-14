// MyOTS outfit shader: Void - a window into deep space: dark purple body full of drifting
// twinkling stars, wrapped in a pulsing violet aura (loyalty store).
const float offset = 1.0 / 64.0;
uniform float u_Time;
uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;

float hash(vec2 p)
{
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float stars(vec2 uv, float density, float speed)
{
    vec2 p = uv * density + vec2(u_Time * speed, u_Time * speed * 0.3);
    vec2 cell = floor(p);
    vec2 f = fract(p) - 0.5;
    float h = hash(cell);
    float tw = 0.5 + 0.5 * sin(u_Time * (1.5 + 4.0 * h) + h * 6.2831);
    float s = step(0.88, h) * (1.0 - smoothstep(0.05, 0.3, length(f)));
    return s * tw;
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
            float glow = 0.55 + 0.25 * sin(u_Time * 2.0 + v_TexCoord.y * 20.0);
            gl_FragColor = vec4(vec3(0.6, 0.2, 1.0) * glow, glow);
            return;
        }
        if (col.a < 0.01)
            discard;
        gl_FragColor = col;
        return;
    }

    float lum = dot(col.rgb, vec3(0.299, 0.587, 0.114));
    // nebula: deep indigo to purple, slowly swirling
    float neb = 0.5 + 0.5 * sin(v_TexCoord.x * 9.0 + u_Time * 0.7) * sin(v_TexCoord.y * 7.0 - u_Time * 0.5);
    vec3 space = mix(vec3(0.03, 0.0, 0.08), vec3(0.3, 0.05, 0.45), neb * 0.7 + lum * 0.5);
    vec3 rgb = mix(col.rgb, space, 0.85);

    float s = stars(v_TexCoord, 30.0, 0.15) + stars(v_TexCoord, 55.0, 0.07) * 0.7;
    rgb += vec3(0.95, 0.9, 1.0) * s;

    gl_FragColor = vec4(clamp(rgb, 0.0, 1.0), col.a);
}
