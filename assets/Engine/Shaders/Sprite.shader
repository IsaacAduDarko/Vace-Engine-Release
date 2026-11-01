#type vertex

#version 430 core

layout(location = 0) in vec3 a_Position;
layout(location = 1) in vec2 a_UV;
layout(location = 2) in vec4 a_Color;

uniform mat4 u_ViewProj;
uniform mat4 u_Model;

out vec2 v_UV;
out vec4 v_Color;

void main()
{
    v_UV = a_UV;
    v_Color = a_Color;

    gl_Position = u_ViewProj * u_Model * vec4(a_Position, 1.0);
}

#type fragment

#version 430 core

in vec2 v_UV;
in vec4 v_Color;

out vec4 FragColor;

uniform sampler2D u_AlbedoMap;
uniform vec4      u_AlbedoColor;
uniform vec4      u_UVRect;       // x = u0, y = v0, z = u1, w = v1
uniform float     u_Opacity;
uniform float     u_AlphaCutoff;
uniform int       u_AlphaMode;    // 0 = opaque, 1 = cutout, 2 = blend

// ---- Reserved for the Light2D system ------------------------------
//
// The 2D shader is currently unlit. When Light2D lands, the renderer
// will populate these uniforms and the color math below will be
// extended to accumulate per-light contributions. Today:
//
//   u_Light2DCount     is always 0
//   u_Ambient2DColor   is (1, 1, 1) — a no-op multiplier
//
// Reserving the names now keeps this shader stable when the lighting
// system arrives.
uniform int  u_Light2DCount;
uniform vec3 u_Ambient2DColor;

void main()
{
    // Map the mesh's normalized UV into the sprite rect.
    vec2 uv = mix(u_UVRect.xy, u_UVRect.zw, v_UV);

    vec4 albedo = texture(u_AlbedoMap, uv);
    albedo *= u_AlbedoColor;
    albedo *= v_Color;

    float alpha = albedo.a * u_Opacity;

    if (u_AlphaMode == 1)
    {
        if (alpha < u_AlphaCutoff)
        {
            discard;
        }

        alpha = 1.0;
    }
    else if (u_AlphaMode == 0)
    {
        alpha = 1.0;
    }

    vec3 color = albedo.rgb * u_Ambient2DColor;

    FragColor = vec4(color, alpha);
}