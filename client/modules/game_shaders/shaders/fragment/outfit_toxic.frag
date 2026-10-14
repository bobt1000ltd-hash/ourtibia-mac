// MyOTS outfit shader: Toxic - pulsing radioactive green (loyalty store).
uniform float u_Time;
uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;

void main()
{
    vec4 col = texture2D(u_Tex0, v_TexCoord);
    if (col.a < 0.01)
        discard;

    float lum = dot(col.rgb, vec3(0.299, 0.587, 0.114));
    float pulse = 0.5 + 0.5 * sin(u_Time * 3.0);
    // slow wobbling bands of brighter slime
    float band = 0.5 + 0.5 * sin(v_TexCoord.y * 40.0 + v_TexCoord.x * 12.0 - u_Time * 4.0);

    vec3 toxic = vec3(0.25 + 0.4 * lum, 0.75 + 0.25 * lum, 0.1 + 0.2 * lum);
    vec3 rgb = mix(col.rgb, toxic * (0.6 + 0.6 * lum), 0.65);
    rgb += vec3(0.15, 0.45, 0.05) * pulse * (0.4 + 0.6 * band);

    gl_FragColor = vec4(clamp(rgb, 0.0, 1.0), col.a);
}
