// OurTibia (03.10.2026): unlooted corpse that holds an UNIDENTIFIED item -
// pulsing purple tint (normal unlooted corpses get the light corpse_glow).
uniform float u_Time;
uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;

void main()
{
    vec4 col = texture2D(u_Tex0, v_TexCoord);
    if (col.a < 0.01)
        discard;
    float pulse = 0.38 + 0.17 * sin(u_Time * 4.0);
    col.rgb = mix(col.rgb, vec3(0.78, 0.30, 1.0), pulse);
    gl_FragColor = col;
}
