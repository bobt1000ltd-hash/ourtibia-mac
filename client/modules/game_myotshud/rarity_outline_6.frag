// OurTibia (03.10.2026): rarity outline around the item's shape (6).
// Drawn through a framebuffer (64 px), so 1/64 = one pixel.
uniform float u_Time;
uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;
float near(float o)
{
    float a = texture2D(u_Tex0, v_TexCoord + vec2(o, 0.0)).a + texture2D(u_Tex0, v_TexCoord - vec2(o, 0.0)).a
            + texture2D(u_Tex0, v_TexCoord + vec2(0.0, o)).a + texture2D(u_Tex0, v_TexCoord - vec2(0.0, o)).a;
    float d = o * 0.7071;
    a += texture2D(u_Tex0, v_TexCoord + vec2(d, d)).a + texture2D(u_Tex0, v_TexCoord - vec2(d, d)).a
       + texture2D(u_Tex0, v_TexCoord + vec2(d, -d)).a + texture2D(u_Tex0, v_TexCoord + vec2(-d, d)).a;
    return a;
}
void main()
{
    vec4 col = texture2D(u_Tex0, v_TexCoord);
    if (col.a > 0.5) { gl_FragColor = col; return; }
    const float px = 1.0 / 64.0;
    if (near(px) > 0.3) { gl_FragColor = vec4(1.000, 0.890, 0.420, 1.0); return; }
    if (near(px * 2.0) > 0.3) { gl_FragColor = vec4(1.000, 0.540, 0.000, 0.85); return; }
    gl_FragColor = col;
}
