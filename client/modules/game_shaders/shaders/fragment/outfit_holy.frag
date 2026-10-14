// MyOTS outfit shader: Holy Light - radiant white-gold body with soft light rays and a
// breathing golden halo around the character (loyalty store).
const float offset = 1.0 / 64.0;
uniform float u_Time;
uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;

void main()
{
    float breath = 0.5 + 0.5 * sin(u_Time * 2.2);

    vec4 col = texture2D(u_Tex0, v_TexCoord);
    if (col.a < 0.5) {
        // two-step halo: bright inner ring, softer outer ring
        float a1 = texture2D(u_Tex0, v_TexCoord + vec2(offset, 0.0)).a +
                   texture2D(u_Tex0, v_TexCoord - vec2(offset, 0.0)).a +
                   texture2D(u_Tex0, v_TexCoord + vec2(0.0, offset)).a +
                   texture2D(u_Tex0, v_TexCoord - vec2(0.0, offset)).a;
        float a2 = texture2D(u_Tex0, v_TexCoord + vec2(offset, offset) * 2.0).a +
                   texture2D(u_Tex0, v_TexCoord - vec2(offset, offset) * 2.0).a +
                   texture2D(u_Tex0, v_TexCoord + vec2(offset, -offset) * 2.0).a +
                   texture2D(u_Tex0, v_TexCoord - vec2(offset, -offset) * 2.0).a +
                   texture2D(u_Tex0, v_TexCoord + vec2(offset * 2.0, 0.0)).a +
                   texture2D(u_Tex0, v_TexCoord - vec2(offset * 2.0, 0.0)).a +
                   texture2D(u_Tex0, v_TexCoord + vec2(0.0, offset * 2.0)).a +
                   texture2D(u_Tex0, v_TexCoord - vec2(0.0, offset * 2.0)).a;
        float glow = 0.0;
        if (a1 > 0.0)
            glow = 0.75 + 0.25 * breath;
        else if (a2 > 0.0)
            glow = (0.2 + 0.25 * breath) * min(a2, 1.0);
        if (glow > 0.0) {
            gl_FragColor = vec4(vec3(1.0, 0.92, 0.6) * glow, glow);
            return;
        }
        if (col.a < 0.01)
            discard;
        gl_FragColor = col;
        return;
    }

    float lum = dot(col.rgb, vec3(0.299, 0.587, 0.114));
    vec3 holy = mix(vec3(0.75, 0.6, 0.3), vec3(1.0, 1.0, 0.92), lum);
    vec3 rgb = mix(col.rgb, holy, 0.65);

    // slowly rotating light rays from the centre of the outfit
    vec2 c = v_TexCoord - vec2(0.5, 0.5);
    float ang = atan(c.y, c.x + 0.0001);
    float rays = pow(0.5 + 0.5 * sin(ang * 8.0 + u_Time * 1.5), 6.0);
    rgb += vec3(1.0, 0.95, 0.75) * (rays * 0.35 + breath * 0.15);

    gl_FragColor = vec4(clamp(rgb, 0.0, 1.0), col.a);
}
