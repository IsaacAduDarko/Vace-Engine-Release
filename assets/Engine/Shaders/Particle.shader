#type vertex
#version 430 core

// Instanced particle shader. Per-particle data comes from a texture
// buffer, 4 texels per particle:
//   0: position.xyz (world), size
//   1: color rgba
//   2: cards: rotation (rad), seed, flipbook frame, age01
//      mesh : orientation quaternion xyzw
//   3: velocity.xyz (world), seed (mesh)

layout(location = 0) in vec3 a_Position;
layout(location = 1) in vec3 a_Normal;
layout(location = 2) in vec2 a_UV;

uniform samplerBuffer u_Instances;
uniform mat4 u_ViewProj;
uniform vec3 u_CameraPosition;
uniform int u_Plane2D;

// 0 billboard, 1 stretched, 2 horizontal, 3 vertical, 4 mesh
uniform int u_RenderMode;
uniform float u_VelocityStretch;
uniform ivec2 u_SheetTiles;

out vec2 v_UV;
out vec2 v_Local;          // card space, -1..1
out vec4 v_Color;
out vec3 v_WorldPos;
out vec3 v_Normal;         // mesh normal / card facing
out vec3 v_Right;
out vec3 v_Up;
out vec3 v_Forward;        // card normal (toward camera)
flat out float v_Seed;
out float v_Age;

vec3 RotateByQuat(vec3 v, vec4 q)
{
    vec3 t = 2.0 * cross(q.xyz, v);
    return v + q.w * t + cross(q.xyz, t);
}

void main()
{
    int base = gl_InstanceID * 4;
    vec4 t0 = texelFetch(u_Instances, base + 0);
    vec4 t1 = texelFetch(u_Instances, base + 1);
    vec4 t2 = texelFetch(u_Instances, base + 2);
    vec4 t3 = texelFetch(u_Instances, base + 3);

    vec3 center = t0.xyz;
    float size = t0.w;

    v_Color = t1;

    if (u_RenderMode == 4)
    {
        vec3 local = RotateByQuat(a_Position * size, t2);
        vec3 world = center + local;

        v_WorldPos = world;
        v_Normal = normalize(RotateByQuat(a_Normal, t2));
        v_UV = a_UV;
        v_Local = a_Position.xy * 2.0;
        v_Seed = t3.w;
        v_Age = 0.0;
        v_Right = vec3(1.0, 0.0, 0.0);
        v_Up = vec3(0.0, 1.0, 0.0);
        v_Forward = v_Normal;

        gl_Position = u_ViewProj * vec4(world, 1.0);
        return;
    }

    vec3 toCamera = u_CameraPosition - center;
    float distanceToCamera = length(toCamera);
    toCamera = (distanceToCamera > 1e-5) ? toCamera / distanceToCamera : vec3(0.0, 0.0, 1.0);

    // 2D emitters: an orthographic 2D camera sits in the particles' own
    // plane, so "face the camera" would turn cards edge-on. Cards always
    // lie in XY facing +Z instead.
    if (u_Plane2D != 0)
    {
        toCamera = vec3(0.0, 0.0, 1.0);
    }

    vec3 worldUp = vec3(0.0, 1.0, 0.0);
    vec3 right;
    vec3 up;
    vec3 forward = toCamera;

    if (u_Plane2D != 0 && u_RenderMode != 1)
    {
        right = vec3(1.0, 0.0, 0.0);
        up = vec3(0.0, 1.0, 0.0);
    }
    else if (u_RenderMode == 2)
    {
        // Flat on the ground plane.
        right = vec3(1.0, 0.0, 0.0);
        up = vec3(0.0, 0.0, -1.0);
        forward = vec3(0.0, 1.0, 0.0);
    }
    else if (u_RenderMode == 3)
    {
        // Upright, turning around Y to face the camera.
        vec3 level = vec3(toCamera.x, 0.0, toCamera.z);
        level = (dot(level, level) > 1e-6) ? normalize(level) : vec3(0.0, 0.0, 1.0);
        right = normalize(cross(worldUp, level));
        up = worldUp;
        forward = level;
    }
    else if (u_RenderMode == 1 && dot(t3.xyz, t3.xyz) > 1e-6)
    {
        // Stretched along velocity, rotated around it to face the camera.
        vec3 axis = normalize(t3.xyz);
        right = cross(axis, toCamera);
        right = (dot(right, right) > 1e-6) ? normalize(right) : vec3(1.0, 0.0, 0.0);
        up = axis * (1.0 + length(t3.xyz) * u_VelocityStretch);
    }
    else
    {
        right = cross(worldUp, toCamera);
        right = (dot(right, right) > 1e-6) ? normalize(right) : vec3(1.0, 0.0, 0.0);
        up = cross(toCamera, right);
    }

    vec2 corner = a_Position.xy;

    // Card spin (not for stretched cards, which align to velocity).
    if (u_RenderMode != 1)
    {
        float c = cos(t2.x);
        float s = sin(t2.x);
        corner = vec2(c * corner.x - s * corner.y, s * corner.x + c * corner.y);
    }

    vec3 world = center + (right * corner.x + up * corner.y) * size;

    // Flipbook tile.
    int frames = max(1, u_SheetTiles.x * u_SheetTiles.y);
    int frame = int(mod(t2.z, float(frames)));
    vec2 tileSize = vec2(1.0) / vec2(u_SheetTiles);
    vec2 tile = vec2(float(frame % u_SheetTiles.x), float(u_SheetTiles.y - 1 - frame / u_SheetTiles.x));

    v_UV = (tile + a_UV) * tileSize;
    v_Local = a_Position.xy * 2.0;
    v_WorldPos = world;
    v_Right = normalize(right);
    v_Up = normalize(up);
    v_Forward = forward;
    v_Normal = forward;
    v_Seed = t2.y;
    v_Age = t2.w;

    gl_Position = u_ViewProj * vec4(world, 1.0);
}

#type fragment
#version 430 core

in vec2 v_UV;
in vec2 v_Local;
in vec4 v_Color;
in vec3 v_WorldPos;
in vec3 v_Normal;
in vec3 v_Right;
in vec3 v_Up;
in vec3 v_Forward;
flat in float v_Seed;
in float v_Age;

out vec4 FragColor;

uniform int u_RenderMode;
uniform int u_Shading;        // 0 unlit, 1 lit, 2 volumetric
uniform int u_BlendMode;      // 0 alpha, 1 additive, 2 premultiplied, 3 opaque
uniform int u_HasTexture;
uniform sampler2D u_Texture;

uniform float u_Softness;
uniform float u_Emissive;
uniform float u_VolumeDensity;
uniform float u_Scattering;
uniform float u_Time;

uniform vec3 u_CameraPosition;
uniform vec3 u_AmbientColor;
uniform int u_HasIrradiance;
uniform samplerCube u_Irradiance;
uniform float u_EnvironmentIntensity;

#define MAX_LIGHTS 8
uniform int u_LightCount;
uniform int u_LightType[MAX_LIGHTS];        // 0 directional, 1 point, 2 spot
uniform vec3 u_LightPosition[MAX_LIGHTS];
uniform vec3 u_LightDirection[MAX_LIGHTS];
uniform vec3 u_LightColor[MAX_LIGHTS];
uniform float u_LightIntensity[MAX_LIGHTS];
uniform float u_LightRange[MAX_LIGHTS];
uniform float u_LightInnerCos[MAX_LIGHTS];
uniform float u_LightOuterCos[MAX_LIGHTS];

// ---- Noise ---------------------------------------------------------

float Hash(vec3 p)
{
    p = fract(p * 0.3183099 + 0.1);
    p *= 17.0;
    return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float ValueNoise(vec3 x)
{
    vec3 i = floor(x);
    vec3 f = fract(x);
    f = f * f * (3.0 - 2.0 * f);

    return mix(mix(mix(Hash(i + vec3(0, 0, 0)), Hash(i + vec3(1, 0, 0)), f.x),
                   mix(Hash(i + vec3(0, 1, 0)), Hash(i + vec3(1, 1, 0)), f.x), f.y),
               mix(mix(Hash(i + vec3(0, 0, 1)), Hash(i + vec3(1, 0, 1)), f.x),
                   mix(Hash(i + vec3(0, 1, 1)), Hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float Fbm(vec3 p)
{
    float sum = 0.0;
    float amplitude = 0.5;

    for (int i = 0; i < 4; ++i)
    {
        sum += ValueNoise(p) * amplitude;
        p = p * 2.03 + vec3(1.7, 9.2, 3.1);
        amplitude *= 0.5;
    }

    return sum;
}

// ---- Lighting ------------------------------------------------------

// Wrapped diffuse (soft terminator) plus forward scattering for volumes.
vec3 ShadeLights(vec3 position, vec3 normal, vec3 viewDir, float wrap, float scatter)
{
    vec3 result = vec3(0.0);

    for (int i = 0; i < u_LightCount && i < MAX_LIGHTS; ++i)
    {
        vec3 toLight;
        float attenuation = 1.0;

        if (u_LightType[i] == 0)
        {
            toLight = -normalize(u_LightDirection[i]);
        }
        else
        {
            vec3 delta = u_LightPosition[i] - position;
            float distance = length(delta);
            toLight = delta / max(distance, 1e-4);

            float range = max(u_LightRange[i], 1e-3);
            float falloff = clamp(1.0 - pow(distance / range, 4.0), 0.0, 1.0);
            attenuation = falloff * falloff / (distance * distance + 1.0);

            if (u_LightType[i] == 2)
            {
                float cosTheta = dot(-toLight, normalize(u_LightDirection[i]));
                attenuation *= smoothstep(u_LightOuterCos[i], u_LightInnerCos[i], cosTheta);
            }
        }

        vec3 radiance = u_LightColor[i] * u_LightIntensity[i] * attenuation;

        float diffuse = clamp((dot(normal, toLight) + wrap) / (1.0 + wrap), 0.0, 1.0);

        // Light coming through the volume toward the eye.
        float forward = pow(clamp(dot(-viewDir, toLight), 0.0, 1.0), 6.0) * scatter;

        result += radiance * (diffuse + forward);
    }

    return result;
}

vec3 Ambient(vec3 normal)
{
    vec3 ambient = u_AmbientColor;

    if (u_HasIrradiance != 0)
    {
        ambient += texture(u_Irradiance, normal).rgb * u_EnvironmentIntensity;
    }

    return ambient;
}

void main()
{
    vec4 base = v_Color;
    float radius = length(v_Local);

    if (u_RenderMode != 4)
    {
        if (u_HasTexture != 0)
        {
            base *= texture(u_Texture, v_UV);
        }
        else
        {
            // Procedural soft disc.
            float softness = clamp(u_Softness, 0.001, 1.0);
            base.a *= 1.0 - smoothstep(1.0 - softness, 1.0, radius);
        }
    }
    else if (u_HasTexture != 0)
    {
        base *= texture(u_Texture, v_UV);
    }

    vec3 viewDir = normalize(v_WorldPos - u_CameraPosition);
    vec3 color = base.rgb;

    if (u_RenderMode == 4)
    {
        // Mesh particles (debris): plain wrapped diffuse.
        if (u_Shading != 0)
        {
            vec3 n = normalize(v_Normal);
            color = base.rgb * (Ambient(n) + ShadeLights(v_WorldPos, n, viewDir, 0.1, 0.0));
        }
    }
    else if (u_Shading != 0)
    {
        // Treat the card as the front of a sphere so it shades like a
        // volume instead of a flat sprite.
        vec2 p = clamp(v_Local, vec2(-1.0), vec2(1.0));
        float z = sqrt(max(0.0, 1.0 - dot(p, p)));
        vec3 sphereNormal = normalize(v_Right * p.x + v_Up * p.y + v_Forward * max(z, 0.25));

        float scatter = 0.0;

        if (u_Shading == 2)
        {
            // Animated density: billowing noise, evolving with age.
            vec3 q = vec3(p * 1.6, v_Seed * 37.0) + vec3(0.0, -v_Age * 1.2, u_Time * 0.15);
            float density = Fbm(q * 2.2);
            density = clamp((density - 0.25) * (1.0 + u_VolumeDensity * 2.0) + 0.35, 0.0, 1.0);

            // Thicker in the middle, wispy at the rim.
            base.a *= density * mix(1.0, z, 0.6);

            // Self-shadowing: denser parts read darker.
            color *= mix(1.0, 0.65 + 0.35 * density, clamp(u_VolumeDensity, 0.0, 1.0));

            scatter = u_Scattering;
        }

        vec3 lighting = Ambient(sphereNormal) + ShadeLights(v_WorldPos, sphereNormal, viewDir, 0.6, scatter);
        color *= lighting;
    }

    color += base.rgb * u_Emissive;

    if (u_BlendMode == 3)
    {
        if (base.a < 0.5)
        {
            discard;
        }

        FragColor = vec4(color, 1.0);
        return;
    }

    if (base.a <= 0.003)
    {
        discard;
    }

    if (u_BlendMode == 2)
    {
        FragColor = vec4(color * base.a, base.a);
    }
    else
    {
        FragColor = vec4(color, clamp(base.a, 0.0, 1.0));
    }
}
