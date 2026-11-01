#type vertex

#version 430 core

layout(location = 0) in vec3 a_Position;
layout(location = 1) in vec2 a_UV;
layout(location = 2) in vec4 a_Color;

uniform mat4 u_ViewProj;   // pixel-space ortho, y-down
uniform mat4 u_Model;      // unit quad scaled to rect size, translated to rect center

out vec2 v_ScreenPos;      // pixel-space fragment position

void main()
{
    // Unit quad vertices are in -0.5..0.5. The model matrix scales
    // them to the element's pixel size and translates them to its
    // center. gl_Position is NDC.
    vec4 clip = u_ViewProj * u_Model * vec4(a_Position, 1.0);
    gl_Position = clip;

    // The ortho maps pixel space directly, so we can recover screen
    // position by undoing the ortho's scale/offset. Easier: pass the
    // model-space position through a second transform that maps
    // directly to pixels. Since u_ViewProj is a pixel ortho, and
    // u_Model already produces pixel-space coordinates (unit quad
    // scaled/translated in pixels), the fragment's pixel position is
    // just (u_Model * vec4(a_Position, 1)).xy.
    v_ScreenPos = (u_Model * vec4(a_Position, 1.0)).xy;
}

#type fragment

#version 430 core

in vec2 v_ScreenPos;

out vec4 FragColor;

// Screen-space rect: xy = top-left, zw = size, in pixels.
uniform vec4  u_Rect;

// Corner radius in pixels. 0 = square corners.
uniform float u_Radius;

// Border thickness in pixels. 0 = no border.
uniform float u_BorderWidth;

uniform vec4  u_FillColor;
uniform vec4  u_BorderColor;

// Optional image fill. u_ImageRect is where the texture maps (equals
// u_Rect, or a letterboxed rect when preserving aspect); outside it the
// fill is transparent.
uniform int       u_UseTexture;
uniform sampler2D u_Texture;
uniform vec4      u_ImageRect;

// Signed distance to a rounded box, in pixels. Negative = inside,
// positive = outside. Inigo Quilez's formula.
//
//   p = fragment position relative to the box center
//   b = box half-size
//   r = corner radius (clamped to min(b.x, b.y))
float sdRoundedBox(vec2 p, vec2 b, float r)
{
    r = min(r, min(b.x, b.y));
    vec2 q = abs(p) - b + r;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

void main()
{
    vec2 center = u_Rect.xy + u_Rect.zw * 0.5;
    vec2 boxHalf = u_Rect.zw * 0.5;

    vec2 p = v_ScreenPos - center;

    float d = sdRoundedBox(p, boxHalf, u_Radius);

    if (d > 0.0)
    {
        // Outside the box entirely. Corners of a rounded rect fall
        // here when radius > 0.
        discard;
    }

    if (u_BorderWidth > 0.0 && d > -u_BorderWidth)
    {
        FragColor = u_BorderColor;
    }
    else
    {
        vec4 fill = u_FillColor;

        if (u_UseTexture != 0)
        {
            vec2 uv = (v_ScreenPos - u_ImageRect.xy) / max(u_ImageRect.zw, vec2(1e-4));

            if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0))))
            {
                discard;
            }

            fill *= texture(u_Texture, uv);
        }

        FragColor = fill;
    }
}