// MyOTS outfit shader: Storm - electric blue body, crackling arcs and lightning flashes (loyalty store).
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
    // random flash: changes 12 times a second, strong flash ~15% of the time
    float tick = floor(u_Time * 12.0);
    float flash = step(0.85, hash(vec2(tick, 3.7)));

    vec4 col = texture2D(u_Tex0, v_TexCoord);
    if (col.a < 0.5) {
        float a = texture2D(u_Tex0, v_TexCoord + vec2(offset, 0.0)).a +
                  texture2D(u_Tex0, v_TexCoord - vec2(offset, 0.0)).a +
                  texture2D(u_Tex0, v_TexCoord + vec2(0.0, offset)).a +
                  texture2D(u_Tex0, v_TexCoord - vec2(0.0, offset)).a;
        if (a > 0.0) {
            // crackling rim: segments switch on and off
            float seg = hash(floor(v_TexCoord * 32.0) + vec2(tick, 0.0));
            float on = max(step(0.45, seg), flash);
            float glow = on * (0.6 + 0.4 * flash);
            if (glow < 0.01) {
                if (col.a < 0.01)
                    discard;
                gl_FragColor = col;
                return;
            }
            gl_FragColor = vec4(vec3(0.45, 0.8, 1.0) * glow, glow);
            return;
        }
        if (col.a < 0.01)
            discard;
        gl_FragColor = col;
        return;
    }

    float lum = dot(col.rgb, vec3(0.299, 0.587, 0.114));
    vec3 elec = mix(vec3(0.02, 0.1, 0.4), vec3(0.5, 0.85, 1.0), lum);
    vec3 rgb = mix(col.rgb, elec, 0.75);

    // zig-zag lightning arcs travelling across the outfit
    float zig = abs(fract(v_TexCoord.y * 6.0 + hash(vec2(tick, 1.0))) - 0.5) * 0.25;
    float arcX = fract(hash(vec2(tick, 9.1)) + v_TexCoord.y * 0.3);
    float arc = 1.0 - smoothstep(0.0, 0.03, abs(v_TexCoord.x - arcX - zig));
    rgb += vec3(0.7, 0.9, 1.0) * arc * 0.9;
    rgb += vec3(0.5, 0.7, 1.0) * flash * 0.6;
    rgb *= 0.85 + 0.15 * sin(u_Time * 40.0);

    gl_FragColor = vec4(clamp(rgb, 0.0, 1.0), col.a);
}
