// MyOTS outfit shader: Nebula - drifting pink and blue clouds of a nebula with a soft
// lilac rim (Task Shop, 17.10.2026).
const float offset = 1.0 / 64.0;
uniform float u_Time;
uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;

void main()
{
    vec4 col = texture2D(u_Tex0, v_TexCoord);
    if (col.a < 0.5) {
        float a = texture2D(u_Tex0, v_TexCoord + vec2(offset, 0.0)).a +
                  texture2D(u_Tex0, v_TexCoord - vec2(offset, 0.0)).a +
                  texture2D(u_Tex0, v_TexCoord + vec2(0.0, offset)).a +
                  texture2D(u_Tex0, v_TexCoord - vec2(0.0, offset)).a;
        if (a > 0.0) {
            float glow = 0.45 + 0.2 * sin(u_Time * 1.5 + v_TexCoord.x * 18.0);
            gl_FragColor = vec4(vec3(0.85, 0.55, 1.0) * glow, glow);
            return;
        }
        if (col.a < 0.01)
            discard;
        gl_FragColor = col;
        return;
    }
    float lum = dot(col.rgb, vec3(0.299, 0.587, 0.114));
    float c1 = 0.5 + 0.5 * sin(v_TexCoord.x * 11.0 + u_Time * 0.8 + sin(v_TexCoord.y * 6.0 + u_Time * 0.4));
    float c2 = 0.5 + 0.5 * sin(v_TexCoord.y * 13.0 - u_Time * 0.6 + sin(v_TexCoord.x * 5.0));
    vec3 cloud = mix(vec3(0.15, 0.25, 0.75), vec3(0.95, 0.35, 0.75), c1);
    cloud = mix(cloud, vec3(0.35, 0.85, 0.95), c2 * 0.35);
    vec3 rgb = mix(col.rgb, cloud * (0.45 + 0.75 * lum), 0.75);
    gl_FragColor = vec4(clamp(rgb, 0.0, 1.0), col.a);
}
