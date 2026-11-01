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

uniform samplerCube u_Environment;
uniform int u_Face;

const float PI = 3.14159265359;

vec3 CubeFaceDirection(int face, vec2 uv)
{
    if (face == 0) return normalize(vec3( 1.0, -uv.y, -uv.x));
    if (face == 1) return normalize(vec3(-1.0, -uv.y,  uv.x));
    if (face == 2) return normalize(vec3( uv.x,  1.0,  uv.y));
    if (face == 3) return normalize(vec3( uv.x, -1.0, -uv.y));
    if (face == 4) return normalize(vec3( uv.x, -uv.y,  1.0));
    return normalize(vec3(-uv.x, -uv.y, -1.0));
}

void main()
{
    vec3 N = CubeFaceDirection(u_Face, v_Ndc);

    // Build an arbitrary tangent frame around N.
    vec3 up = abs(N.y) < 0.999 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
    vec3 right = normalize(cross(up, N));
    up = normalize(cross(N, right));

    // Cosine-weighted hemisphere integration. Using a fixed sample
    // pattern rather than random sampling keeps this deterministic and
    // cheap; the irradiance map is small (32x32) and low-frequency, so
    // a modest sample count is visually indistinguishable from a
    // stochastic version.
    const int SAMPLE_STEP = 8;
    const int SAMPLE_COUNT = 128;

    vec3 irradiance = vec3(0.0);
    int accumulated = 0;

    for (int phi = 0; phi < 180; phi += SAMPLE_STEP)
    {
        for (int theta = 0; theta < 360; theta += SAMPLE_STEP)
        {
            float phiRad   = radians(float(phi));
            float thetaRad = radians(float(theta));

            vec3 tangentSample = vec3(
                sin(phiRad) * cos(thetaRad),
                sin(phiRad) * sin(thetaRad),
                cos(phiRad)
            );

            // Tangent sample is in a hemisphere aligned to +Z; rotate
            // into the frame around N.
            vec3 sampleDir =
                tangentSample.x * right +
                tangentSample.y * up +
                tangentSample.z * N;

            irradiance += texture(u_Environment, sampleDir).rgb *
                          cos(phiRad) * sin(phiRad);
        }
    }

    // Account for the number of samples we actually took (a fixed
    // step, so it's constant, but we compute it in case the loop
    // bounds change).
    accumulated = (180 / SAMPLE_STEP) * (360 / SAMPLE_STEP);

    irradiance *= PI / float(accumulated);

    FragColor = vec4(irradiance, 1.0);
}