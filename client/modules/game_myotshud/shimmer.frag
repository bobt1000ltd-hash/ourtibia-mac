// OurTibia: diagonal light sweep (top-left -> bottom-right) over the sprite only.
// Used for unidentified items and unlooted corpses (Mythibia style).
uniform float u_Time;
uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;

void main()
{
    vec4 col = texture2D(u_Tex0, v_TexCoord);
    if (col.a < 0.01)
        discard;
    // Screen space: gl_FragCoord.y grows upwards, so x - y grows towards bottom-right.
    float d = gl_FragCoord.x - gl_FragCoord.y;
    float period = 110.0;
    float p = mod(d - u_Time * 70.0, period);
    float band = smoothstep(0.0, 9.0, p) * (1.0 - smoothstep(9.0, 18.0, p));
    col.rgb = mix(col.rgb, vec3(1.0, 1.0, 1.0), band * 0.6);
    gl_FragColor = col;
}
