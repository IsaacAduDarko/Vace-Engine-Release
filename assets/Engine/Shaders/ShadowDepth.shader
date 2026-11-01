#type vertex

#version 430 core

layout(location = 0) in vec3 a_Position;
layout(location = 5) in uvec4 a_BoneIndices;
layout(location = 6) in vec4 a_BoneWeights;

uniform mat4 u_Model;
uniform mat4 u_LightSpaceMatrix;

const int MAX_BONES = 128;
uniform mat4 u_Bones[MAX_BONES];
uniform int u_BoneCount;

void main()
{
    vec4 position = vec4(a_Position, 1.0);

    float totalWeight =
        a_BoneWeights.x + a_BoneWeights.y +
        a_BoneWeights.z + a_BoneWeights.w;

    if (u_BoneCount > 0 && totalWeight > 0.0001)
    {
        mat4 skin =
            u_Bones[a_BoneIndices.x] * a_BoneWeights.x +
            u_Bones[a_BoneIndices.y] * a_BoneWeights.y +
            u_Bones[a_BoneIndices.z] * a_BoneWeights.z +
            u_Bones[a_BoneIndices.w] * a_BoneWeights.w;

        position = skin * position;
    }

    gl_Position = u_LightSpaceMatrix * u_Model * position;
}

#type fragment

#version 430 core

out vec4 FragColor;

void main()
{
    // Depth-only pass: the FBO has no color attachment (glDrawBuffer
    // is GL_NONE), so this write is discarded. The depth buffer is
    // written by the fixed-function pipeline.
    FragColor = vec4(1.0);
}
