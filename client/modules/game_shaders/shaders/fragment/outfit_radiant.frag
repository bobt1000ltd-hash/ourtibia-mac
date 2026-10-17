// MyOTS outfit shader: Radiant - bright pearl and sky-blue light that breathes, with a
// shining white rim (Task Shop, 17.10.2026).
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
            float glow = 0.6 + 0.3 * sin(u_Time * 2.5);
            gl_FragColor = vec4(vec3(0.9, 0.97, 1.0) * glow, glow);
            return;
        }
        if (col.a < 0.01)
            discard;
        gl_FragColor = col;
        return;
    }
    float lum = dot(col.rgb, vec3(0.299, 0.587, 0.114));
    float breathe = 0.5 + 0.5 * sin(u_Time * 1.8);
    vec3 light = mix(vec3(0.45, 0.7, 0.95), vec3(1.0, 1.0, 0.97), lum);
    vec3 rgb = mix(col.rgb, light, 0.65 + 0.15 * breathe);
    float sparkle = pow(0.5 + 0.5 * sin(v_TexCoord.x * 40.0 + u_Time * 3.0) * sin(v_TexCoord.y * 37.0 - u_Time * 2.0), 12.0);
    rgb += vec3(1.0) * sparkle * 0.5;
    gl_FragColor = vec4(clamp(rgb, 0.0, 1.0), col.a);
}
