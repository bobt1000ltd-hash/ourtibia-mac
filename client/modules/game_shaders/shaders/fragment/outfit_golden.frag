// MyOTS outfit shader: Golden Glow - polished gold with a sweeping shimmer (loyalty store).
uniform float u_Time;
uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;

void main()
{
    vec4 col = texture2D(u_Tex0, v_TexCoord);
    if (col.a < 0.01)
        discard;

    float lum = dot(col.rgb, vec3(0.299, 0.587, 0.114));
    // dark gold -> bright gold ramp keeps the outfit details readable
    vec3 gold = mix(vec3(0.45, 0.28, 0.02), vec3(1.0, 0.86, 0.35), lum);
    vec3 rgb = mix(col.rgb, gold, 0.8);

    // diagonal shine band crossing the outfit every 2.5 s
    float pos = fract(u_Time * 0.4) * 3.0 - 1.0;
    float d = (v_TexCoord.x + v_TexCoord.y) - pos * 2.0;
    float shine = exp(-d * d * 60.0);
    rgb += vec3(1.0, 0.95, 0.7) * shine * 0.7;
    rgb += vec3(0.08, 0.06, 0.0) * (0.5 + 0.5 * sin(u_Time * 2.0));

    gl_FragColor = vec4(clamp(rgb, 0.0, 1.0), col.a);
}
