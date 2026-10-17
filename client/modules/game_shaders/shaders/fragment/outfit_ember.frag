// MyOTS outfit shader: Ember - smouldering charcoal with glowing embers drifting upwards
// (Task Shop, 17.10.2026).
uniform float u_Time;
uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;

float hash(vec2 p)
{
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void main()
{
    vec4 col = texture2D(u_Tex0, v_TexCoord);
    if (col.a < 0.01)
        discard;
    float lum = dot(col.rgb, vec3(0.299, 0.587, 0.114));
    vec3 coal = mix(vec3(0.08, 0.03, 0.02), vec3(0.75, 0.25, 0.05), lum);
    float heat = 0.5 + 0.5 * sin(v_TexCoord.y * 25.0 + u_Time * 2.0 + sin(v_TexCoord.x * 10.0));
    coal += vec3(0.35, 0.1, 0.0) * heat * lum;
    vec2 p = v_TexCoord * 26.0 + vec2(0.0, u_Time * 1.2);
    vec2 cell = floor(p);
    float h = hash(cell);
    float spark = step(0.9, h) * (1.0 - smoothstep(0.05, 0.35, length(fract(p) - 0.5)));
    vec3 rgb = mix(col.rgb, coal, 0.85) + vec3(1.0, 0.6, 0.15) * spark;
    gl_FragColor = vec4(clamp(rgb, 0.0, 1.0), col.a);
}
