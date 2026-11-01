#type vertex

#version 430 core

layout(location = 0) in vec3 a_Position;
layout(location = 1) in vec2 a_UV;
layout(location = 2) in vec4 a_Color;

uniform mat4 u_ViewProj;

out vec2 v_UV;
out vec4 v_Color;

void main()
{
    v_UV = a_UV;
    v_Color = a_Color;
    gl_Position = u_ViewProj * vec4(a_Position, 1.0);
}

#type fragment

#version 430 core

in vec2 v_UV;
in vec4 v_Color;

out vec4 FragColor;

uniform sampler2D u_Atlas;

void main()
{
    float coverage = texture(u_Atlas, v_UV).r;
    if (coverage <= 0.0)
    {
        discard;
    }

    FragColor = vec4(v_Color.rgb, v_Color.a * coverage);
}
