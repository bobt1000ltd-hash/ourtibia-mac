// MyOTS outfit shader: Blood Moon - deep red heartbeat pulse (loyalty store).
uniform float u_Time;
uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;

void main()
{
    vec4 col = texture2D(u_Tex0, v_TexCoord);
    if (col.a < 0.01)
        discard;

    float lum = dot(col.rgb, vec3(0.299, 0.587, 0.114));
    // double "heartbeat" every 1.6 s
    float t = mod(u_Time, 1.6);
    float beat = exp(-pow((t - 0.15) * 14.0, 2.0)) + 0.7 * exp(-pow((t - 0.45) * 14.0, 2.0));

    vec3 blood = vec3(0.55 + 0.6 * lum, 0.05 + 0.15 * lum, 0.06 + 0.12 * lum);
    vec3 rgb = mix(col.rgb, blood, 0.7);
    rgb += vec3(0.45, 0.02, 0.02) * beat;

    gl_FragColor = vec4(clamp(rgb, 0.0, 1.0), col.a);
}
