// MyOTS outfit shader: Aurora - northern lights: flowing curtains of green, teal, blue and
// purple over the outfit, with a shimmering aurora rim (loyalty store).
const float offset = 1.0 / 64.0;
uniform float u_Time;
uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;

vec3 aurora(vec2 uv)
{
    // layered sine waves give soft moving curtains
    float w = sin(uv.x * 7.0 + u_Time * 1.1)
            + sin(uv.y * 5.0 - u_Time * 0.8 + uv.x * 3.0)
            + 0.5 * sin((uv.x + uv.y) * 13.0 + u_Time * 2.3);
    float t = 0.5 + 0.5 * sin(w * 1.2 + u_Time * 0.5);
    vec3 green  = vec3(0.1, 1.0, 0.45);
    vec3 teal   = vec3(0.0, 0.75, 0.85);
    vec3 purple = vec3(0.65, 0.2, 1.0);
    vec3 c = mix(green, teal, smoothstep(0.0, 0.5, t));
    return mix(c, purple, smoothstep(0.5, 1.0, t));
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
            float glow = 0.5 + 0.3 * sin(u_Time * 3.0 + v_TexCoord.x * 25.0 + v_TexCoord.y * 15.0);
            gl_FragColor = vec4(aurora(v_TexCoord + vec2(0.1, 0.0)) * glow, glow);
            return;
        }
        if (col.a < 0.01)
            discard;
        gl_FragColor = col;
        return;
    }

    float lum = dot(col.rgb, vec3(0.299, 0.587, 0.114));
    vec3 a = aurora(v_TexCoord);
    vec3 rgb = mix(col.rgb, a * (0.45 + 0.75 * lum), 0.75);
    // faint bright streaks running through the curtains
    float streak = pow(0.5 + 0.5 * sin(v_TexCoord.x * 30.0 + sin(v_TexCoord.y * 6.0 + u_Time) * 3.0), 8.0);
    rgb += a * streak * 0.35;

    gl_FragColor = vec4(clamp(rgb, 0.0, 1.0), col.a);
}
