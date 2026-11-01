#type vertex

#version 430 core

layout(location = 0) in vec2 a_Position;

out vec2 v_Ndc;

void main()
{
    v_Ndc = a_Position;
    gl_Position = vec4(a_Position, 1.0, 1.0);
}

#type fragment

#version 430 core

in vec2 v_Ndc;

out vec4 FragColor;

uniform sampler2D u_Equirect;
uniform int u_Face;

const float PI = 3.14159265359;

// Builds a world-space direction for a pixel on the given cubemap face.
// Face index follows GL order: +X, -X, +Y, -Y, +Z, -Z.
vec3 CubeFaceDirection(int face, vec2 uv)
{
    // uv is in [-1, 1] on the face.
    if (face == 0) return normalize(vec3( 1.0, -uv.y, -uv.x)); // +X
    if (face == 1) return normalize(vec3(-1.0, -uv.y,  uv.x)); // -X
    if (face == 2) return normalize(vec3( uv.x,  1.0,  uv.y)); // +Y
    if (face == 3) return normalize(vec3( uv.x, -1.0, -uv.y)); // -Y
    if (face == 4) return normalize(vec3( uv.x, -uv.y,  1.0)); // +Z
    return normalize(vec3(-uv.x, -uv.y, -1.0));                // -Z
}

void main()
{
    vec3 dir = CubeFaceDirection(u_Face, v_Ndc);

    // Same equirect mapping used by the sky draw shader, so orientation
    // stays consistent.
    float u = atan(dir.z, dir.x) / (2.0 * PI) + 0.5;
    float v = 0.5 - asin(clamp(dir.y, -1.0, 1.0)) / PI;

    FragColor = vec4(texture(u_Equirect, vec2(u, v)).rgb, 1.0);
}