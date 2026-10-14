// MyOTS outfit shader: Frost - icy blue body, twinkling ice sparkles and a cold rim (loyalty store).
const float offset = 1.0 / 64.0;
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
    if (col.a < 0.5) {
        // frosty rim around the outfit
        float a = texture2D(u_Tex0, v_TexCoord + vec2(offset, 0.0)).a +
                  texture2D(u_Tex0, v_TexCoord - vec2(offset, 0.0)).a +
                  texture2D(u_Tex0, v_TexCoord + vec2(0.0, offset)).a +
                  texture2D(u_Tex0, v_TexCoord - vec2(0.0, offset)).a;
        if (a > 0.0) {
            float glow = 0.45 + 0.15 * sin(u_Time * 2.5 + v_TexCoord.x * 30.0);
            gl_FragColor = vec4(vec3(0.7, 0.9, 1.0) * glow, glow);
            return;
        }
        if (col.a < 0.01)
            discard;
        gl_FragColor = col;
        return;
    }

    float lum = dot(col.rgb, vec3(0.299, 0.587, 0.114));
    vec3 ice = mix(vec3(0.1, 0.3, 0.6), vec3(0.85, 0.97, 1.0), lum);
    vec3 rgb = mix(col.rgb, ice, 0.75);

    // twinkling sparkles: each small cell flashes at its own phase
    vec2 cell = floor(v_TexCoord * 48.0);
    float h = hash(cell);
    float tw = sin(u_Time * (2.0 + 3.0 * h) + h * 6.2831);
    float sparkle = step(0.82, h) * smoothstep(0.75, 1.0, tw);
    rgb += vec3(0.9, 0.97, 1.0) * sparkle;

    gl_FragColor = vec4(clamp(rgb, 0.0, 1.0), col.a);
}
