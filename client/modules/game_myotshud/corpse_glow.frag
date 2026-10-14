// OurTibia: steady highlight for unlooted corpses (01.10.2026). Uniform over the
// whole sprite, so it does not move when the map scrolls with the player.
uniform float u_Time;
uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;

void main()
{
    vec4 col = texture2D(u_Tex0, v_TexCoord);
    if (col.a < 0.01)
        discard;
    col.rgb = mix(col.rgb, vec3(1.0, 0.97, 0.85), 0.32);
    gl_FragColor = col;
}
