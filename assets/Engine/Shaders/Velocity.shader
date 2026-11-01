#type vertex

#version 430 core

// Screen-space velocity for per-entity motion blur. Works for 3D meshes,
// 2D meshes (position is location 0 in both layouts) and skinned meshes
// (u_BoneCount > 0; the same pose is used for both frames, so only node
// motion blurs, not the animation itself).

layout(location = 0) in vec3 a_Position;
layout(location = 5) in uvec4 a_BoneIndices;
layout(location = 6) in vec4 a_BoneWeights;

uniform mat4 u_ViewProj;
uniform mat4 u_PrevViewProj;
uniform mat4 u_Model;
uniform mat4 u_PrevModel;

const int MAX_BONES = 128;
uniform mat4 u_Bones[MAX_BONES];
uniform int u_BoneCount;

out vec4 v_Current;
out vec4 v_Previous;

void main()
{
    vec4 local = vec4(a_Position, 1.0);

    if (u_BoneCount > 0)
    {
        float total = a_BoneWeights.x + a_BoneWeights.y + a_BoneWeights.z + a_BoneWeights.w;

        if (total > 0.0)
        {
            mat4 skin =
                u_Bones[min(int(a_BoneIndices.x), MAX_BONES - 1)] * a_BoneWeights.x +
                u_Bones[min(int(a_BoneIndices.y), MAX_BONES - 1)] * a_BoneWeights.y +
                u_Bones[min(int(a_BoneIndices.z), MAX_BONES - 1)] * a_BoneWeights.z +
                u_Bones[min(int(a_BoneIndices.w), MAX_BONES - 1)] * a_BoneWeights.w;

            local = skin * local;
        }
    }

    v_Current = u_ViewProj * u_Model * local;
    v_Previous = u_PrevViewProj * u_PrevModel * local;
    gl_Position = v_Current;
}

#type fragment

#version 430 core

in vec4 v_Current;
in vec4 v_Previous;

out vec4 FragColor;

// Scene shutter * the entity's own intensity.
uniform float u_Scale;

void main()
{
    vec2 current = v_Current.xy / v_Current.w;
    vec2 previous = v_Previous.xy / max(v_Previous.w, 1e-5);

    // NDC delta -> UV delta.
    FragColor = vec4((current - previous) * 0.5 * u_Scale, 0.0, 1.0);
}
