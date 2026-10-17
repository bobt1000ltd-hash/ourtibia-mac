// MyOTS outfit shader: Eclipse - the outfit turns dark as a covered sun, framed by a
// burning orange corona that slowly flares (Task Shop, 17.10.2026).
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
                  texture2D(u_Tex0, v_TexCoord - vec2(0.0, offset)).a +
                  texture2D(u_Tex0, v_TexCoord + vec2(offset, offset) * 2.0).a +
                  texture2D(u_Tex0, v_TexCoord - vec2(offset, offset) * 2.0).a;
        if (a > 0.0) {
            float flare = 0.6 + 0.4 * sin(u_Time * 3.0 + atan(v_TexCoord.y - 0.5, v_TexCoord.x - 0.5) * 6.0);
            gl_FragColor = vec4(vec3(1.0, 0.55, 0.1) * flare, 0.85 * flare);
            return;
        }
        if (col.a < 0.01)
            discard;
        gl_FragColor = col;
        return;
    }
    float lum = dot(col.rgb, vec3(0.299, 0.587, 0.114));
    vec3 dark = mix(vec3(0.02, 0.01, 0.03), vec3(0.22, 0.14, 0.12), lum);
    vec3 rgb = mix(col.rgb, dark, 0.85);
    gl_FragColor = vec4(clamp(rgb, 0.0, 1.0), col.a);
}
