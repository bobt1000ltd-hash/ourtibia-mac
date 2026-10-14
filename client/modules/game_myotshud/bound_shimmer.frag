// OurTibia: golden light sweep for soulbound (Task Shop) items.
uniform float u_Time;
uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;

void main()
{
    vec4 col = texture2D(u_Tex0, v_TexCoord);
    if (col.a < 0.01)
        discard;
    float d = gl_FragCoord.x - gl_FragCoord.y;
    float period = 90.0;
    float p = mod(d - u_Time * 55.0, period);
    float band = smoothstep(0.0, 10.0, p) * (1.0 - smoothstep(10.0, 20.0, p));
    vec3 gold = vec3(1.0, 0.84, 0.32);
    col.rgb = mix(col.rgb, col.rgb * 0.85 + gold * 0.15, 1.0);
    col.rgb = mix(col.rgb, gold, band * 0.7);
    gl_FragColor = col;
}
