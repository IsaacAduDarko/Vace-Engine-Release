#type vertex

#version 430 core

layout(location = 0) in vec3 a_Position;
layout(location = 1) in vec3 a_Normal;
layout(location = 2) in vec2 a_UV;
layout(location = 3) in vec3 a_Tangent;
layout(location = 4) in vec4 a_Color;

uniform mat4 u_ViewProj;
uniform mat4 u_Model;

// Per-axis UV scale. Only consulted when u_UVMode != 0.
// When a primitive is scaled up and the material opts into tiling,
// the UVs are multiplied by the mesh's world-space extent along the
// face's dominant normal axis so the texture tiles instead of
// stretching.
uniform vec3 u_UVScale = vec3(1.0);

// 0 = leave a_UV untouched (Authored, PerFace, every loaded mesh).
// 1 = apply world-space tiling (built-ins with UVMode::Tiled).
// Anything else is treated as 1 for forwards compatibility.
uniform int u_UVMode = 0;

out vec3 v_FragPos;
out vec3 v_Normal;
out vec2 v_UV;
out vec4 v_Color;

// @VACE_VERTEX_DECLARATIONS

void main()
{
    vec4 world = u_Model * vec4(a_Position, 1.0);

    v_FragPos = world.xyz;

    mat3 normalMatrix = transpose(inverse(mat3(u_Model)));
    v_Normal = normalize(normalMatrix * a_Normal);

    vec2 uv = a_UV;

    if (u_UVMode != 0)
    {
        // Pick the axis the normal points along most strongly. Using
        // the dominant axis instead of blending all three guarantees
        // uvScale == 1 whenever u_UVScale == (1,1,1), which is what
        // Authored and PerFace rely on. The old blend formula summed
        // absN.x + absN.y + absN.z, which is 1 only for axis-aligned
        // normals and up to sqrt(3) on curved surfaces — that was the
        // regression that tore up loaded meshes.
        vec3 absN = abs(normalize(a_Normal));

        float axisScale;

        if (absN.x >= absN.y && absN.x >= absN.z)
        {
            axisScale = u_UVScale.x;
        }
        else if (absN.y >= absN.z)
        {
            axisScale = u_UVScale.y;
        }
        else
        {
            axisScale = u_UVScale.z;
        }

        uv *= axisScale;
    }

    v_UV    = uv;
    v_Color = a_Color;

    // @VACE_VERTEX_OFFSET

    gl_Position = u_ViewProj * world;
}


#type fragment

#version 430 core

in vec3 v_FragPos;
in vec3 v_Normal;
in vec2 v_UV;
in vec4 v_Color;

out vec4 FragColor;

// ---- Material ----
uniform sampler2D u_AlbedoMap;
uniform vec4      u_AlbedoColor;

uniform sampler2D u_NormalMap;
uniform float     u_NormalStrength;

uniform sampler2D u_RoughnessMap;
uniform float     u_Roughness;

uniform sampler2D u_MetallicMap;
uniform float     u_Metallic;

uniform sampler2D u_EmissiveMap;
uniform vec4      u_EmissiveColor;
uniform float     u_EmissiveStrength;

uniform sampler2D u_AOMap;
uniform float     u_AOStrength;

uniform float     u_Opacity;
uniform float     u_AlphaCutoff;
uniform int       u_AlphaMode;   // 0 opaque, 1 cutout, 2 blend

// ---- Environment ----
// With an HDRI: image-based lighting. Without: a sky/ground hemisphere.
uniform int         u_HasIBL;
uniform samplerCube u_Irradiance;
uniform samplerCube u_Prefiltered;
uniform sampler2D   u_BRDFLut;
uniform float       u_EnvironmentIntensity;
uniform mat3        u_EnvRotation;     // rotates world directions into HDRI space
uniform vec3        u_SkyColor;        // hemisphere ambient (no HDRI)
uniform vec3        u_GroundColor;

// ---- Camera ----
uniform vec3 u_CameraPosition;

// ---- Direct lights ----
const int MAX_LIGHTS = 8;

uniform int   u_LightCount;
uniform int   u_LightType[MAX_LIGHTS];
uniform vec3  u_LightPosition[MAX_LIGHTS];
uniform vec3  u_LightDirection[MAX_LIGHTS];
uniform vec3  u_LightColor[MAX_LIGHTS];
uniform float u_LightIntensity[MAX_LIGHTS];
uniform float u_LightRange[MAX_LIGHTS];
uniform float u_LightInnerCos[MAX_LIGHTS];
uniform float u_LightOuterCos[MAX_LIGHTS];

uniform vec3 u_AmbientColor;

// ---- Shadows (directional) ----
uniform sampler2D u_ShadowMap;
uniform mat4      u_LightSpaceMatrix;
uniform float     u_ShadowBias;
uniform float     u_ShadowNormalBias;
uniform int       u_ShadowsEnabled;
uniform vec2      u_ShadowTexelSize;
uniform int       u_PCFLevel;
uniform float     u_ShadowSharpness;
uniform vec3      u_ShadowColor;

const float PI = 3.14159265359;

const vec2 POISSON[16] = vec2[](
    vec2(-0.94201624, -0.39906216), vec2( 0.94558609, -0.76890725),
    vec2(-0.09418410, -0.92938870), vec2( 0.34495938,  0.29387760),
    vec2(-0.91588581,  0.45771432), vec2(-0.81544232, -0.87912464),
    vec2(-0.38277543,  0.27676845), vec2( 0.97484398,  0.75648379),
    vec2( 0.44323325, -0.97511554), vec2( 0.53742981, -0.47373420),
    vec2(-0.26496911, -0.41893023), vec2( 0.79197514,  0.19090188),
    vec2(-0.24188840,  0.99706507), vec2(-0.81409955,  0.91437590),
    vec2( 0.19984126,  0.78641367), vec2( 0.14383161, -0.14100790));

float InterleavedGradientNoise(vec2 pixel)
{
    return fract(52.9829189 * fract(dot(pixel, vec2(0.06711056, 0.00583715))));
}

// 0.0 (in shadow) .. 1.0 (lit). PCF level picks the filter radius; the
// Poisson kernel is rotated per pixel so soft edges show fine noise
// instead of blocky steps. Sharpness lerps toward a single hard tap.
float ShadowFactor(vec3 worldPos, vec3 normal, vec3 lightDir)
{
    if (u_ShadowsEnabled == 0)
    {
        return 1.0;
    }

    float ndl = clamp(dot(normal, lightDir), 0.0, 1.0);

    // Normal + slope-scaled bias: surfaces at grazing angles need more.
    vec3 biasedPos = worldPos + normal * u_ShadowNormalBias * (1.0 - ndl * 0.5);
    vec4 lightSpace = u_LightSpaceMatrix * vec4(biasedPos, 1.0);

    vec3 proj = lightSpace.xyz / max(lightSpace.w, 1e-6);
    vec2 uv = proj.xy * 0.5 + 0.5;

    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0 || proj.z > 1.0)
    {
        return 1.0;
    }

    float depth = proj.z * 0.5 + 0.5;
    float tanAngle = sqrt(max(1.0 - ndl * ndl, 0.0)) / max(ndl, 0.05);
    float bias = u_ShadowBias * (1.0 + min(tanAngle, 4.0));

    float hardLit = (depth - bias > texture(u_ShadowMap, uv).r) ? 0.0 : 1.0;

    int level = max(u_PCFLevel, 0);

    if (level == 0)
    {
        return hardLit;
    }

    float angle = InterleavedGradientNoise(gl_FragCoord.xy) * 6.2831853;
    mat2 rotation = mat2(cos(angle), sin(angle), -sin(angle), cos(angle));
    vec2 radius = u_ShadowTexelSize * (float(level) + 0.5);

    float lit = 0.0;

    for (int i = 0; i < 16; ++i)
    {
        vec2 sampleUV = uv + rotation * POISSON[i] * radius;
        lit += (depth - bias > texture(u_ShadowMap, sampleUV).r) ? 0.0 : 1.0;
    }

    float softLit = lit / 16.0;

    return mix(softLit, hardLit, clamp(u_ShadowSharpness, 0.0, 1.0));
}

float DistributionGGX(vec3 n, vec3 h, float roughness)
{
    float a = roughness * roughness;
    float a2 = a * a;
    float ndh = max(dot(n, h), 0.0);
    float denom = ndh * ndh * (a2 - 1.0) + 1.0;
    return a2 / max(PI * denom * denom, 1e-4);
}

float GeometrySchlickGGX(float ndv, float roughness)
{
    float r = roughness + 1.0;
    float k = (r * r) / 8.0;
    return ndv / max(ndv * (1.0 - k) + k, 1e-4);
}

float GeometrySmith(vec3 n, vec3 v, vec3 l, float roughness)
{
    return GeometrySchlickGGX(max(dot(n, v), 0.0), roughness) *
           GeometrySchlickGGX(max(dot(n, l), 0.0), roughness);
}

vec3 FresnelSchlick(float cosTheta, vec3 f0)
{
    return f0 + (1.0 - f0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}

vec3 FresnelSchlickRoughness(float cosTheta, vec3 f0, float roughness)
{
    return f0 + (max(vec3(1.0 - roughness), f0) - f0) *
        pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}

// Hemisphere ambient: sky above, ground below, soft horizon.
vec3 HemisphereAmbient(vec3 dir)
{
    float t = clamp(dir.y * 0.5 + 0.5, 0.0, 1.0);
    return mix(u_GroundColor, u_SkyColor, smoothstep(0.0, 1.0, t));
}

// @VACE_FRAGMENT_DECLARATIONS

// Geometric normal, flipped for back faces of double-sided materials.
vec3 VACE_GeometryNormal()
{
    vec3 n = normalize(v_Normal);
    return gl_FrontFacing ? n : -n;
}

// Applies a tangent-space normal (xyz in -1..1) to `n` using a TBN built
// from screen-space derivatives (no tangent attribute needed).
vec3 VACE_PerturbNormal(vec3 n, vec3 tangentNormal, float strength)
{
    if (strength <= 0.0)
    {
        return n;
    }

    vec3 dp1 = dFdx(v_FragPos);
    vec3 dp2 = dFdy(v_FragPos);
    vec2 duv1 = dFdx(v_UV);
    vec2 duv2 = dFdy(v_UV);

    vec3 dp2perp = cross(dp2, n);
    vec3 dp1perp = cross(n, dp1);
    vec3 t = dp2perp * duv1.x + dp1perp * duv2.x;
    vec3 b = dp2perp * duv1.y + dp1perp * duv2.y;

    float invmax = inversesqrt(max(max(dot(t, t), dot(b, b)), 1e-12));
    mat3 tbn = mat3(t * invmax, b * invmax, n);

    return normalize(mix(n, normalize(tbn * tangentNormal), strength));
}

void main()
{
    // ---- Surface inputs ----
    // Everything lighting needs from the material. Shader-graph generated
    // shaders replace the block between the markers with their own code
    // that assigns the same variables.
    vec4  albedo    = vec4(1.0);
    float alpha     = 1.0;
    float roughness = 0.5;
    float metallic  = 0.0;
    float ao        = 1.0;
    vec3  n         = VACE_GeometryNormal();
    vec3  emissive  = vec3(0.0);

    // @VACE_SURFACE_BEGIN
    albedo = texture(u_AlbedoMap, v_UV) * u_AlbedoColor;
    alpha = albedo.a * u_Opacity;
    roughness = texture(u_RoughnessMap, v_UV).r * u_Roughness;
    metallic = texture(u_MetallicMap, v_UV).r * u_Metallic;
    ao = mix(1.0, texture(u_AOMap, v_UV).r, u_AOStrength);
    n = VACE_PerturbNormal(n, texture(u_NormalMap, v_UV).xyz * 2.0 - 1.0, u_NormalStrength);
    emissive = texture(u_EmissiveMap, v_UV).rgb * u_EmissiveColor.rgb * u_EmissiveStrength;
    // @VACE_SURFACE_END

    roughness = clamp(roughness, 0.03, 1.0);
    metallic  = clamp(metallic, 0.0, 1.0);
    ao        = clamp(ao, 0.0, 1.0);

    if (u_AlphaMode == 1)
    {
        if (alpha < u_AlphaCutoff) { discard; }
        alpha = 1.0;
    }
    else if (u_AlphaMode == 0)
    {
        alpha = 1.0;
    }

    vec3 view = normalize(u_CameraPosition - v_FragPos);
    float ndv = clamp(dot(n, view), 1e-4, 1.0);

    vec3 f0 = mix(vec3(0.04), albedo.rgb, metallic);

    // ---- Direct lighting ----
    vec3 direct = vec3(0.0);

    for (int i = 0; i < u_LightCount && i < MAX_LIGHTS; ++i)
    {
        vec3 lightDir;
        vec3 attenuation = vec3(1.0);

        if (u_LightType[i] == 0) // directional
        {
            lightDir = normalize(-u_LightDirection[i]);

            float shadowLit = ShadowFactor(v_FragPos, n, lightDir);
            attenuation = mix(vec3(1.0), u_ShadowColor, 1.0 - shadowLit);
        }
        else // point or spot
        {
            vec3 toLight = u_LightPosition[i] - v_FragPos;
            float distance = length(toLight);
            float range = max(u_LightRange[i], 1e-3);

            if (distance > range)
            {
                continue;
            }

            lightDir = toLight / max(distance, 1e-4);

            // Inverse-square with a smooth window to zero at the range
            // (Karis, "Real Shading in UE4").
            float ratio = distance / range;
            float window = clamp(1.0 - ratio * ratio * ratio * ratio, 0.0, 1.0);
            attenuation = vec3(window * window / (distance * distance + 1.0));

            if (u_LightType[i] == 2) // spot
            {
                float cosAngle = dot(-lightDir, normalize(u_LightDirection[i]));
                float spot = smoothstep(u_LightOuterCos[i], u_LightInnerCos[i], cosAngle);
                attenuation *= spot * spot;
            }
        }

        float ndl = max(dot(n, lightDir), 0.0);

        if (ndl <= 0.0)
        {
            continue;
        }

        vec3 halfway = normalize(view + lightDir);

        float ndf = DistributionGGX(n, halfway, roughness);
        float geometry = GeometrySmith(n, view, lightDir, roughness);
        vec3 fresnel = FresnelSchlick(max(dot(halfway, view), 0.0), f0);

        vec3 specular = (ndf * geometry * fresnel) / max(4.0 * ndv * ndl, 1e-4);

        vec3 kd = (1.0 - fresnel) * (1.0 - metallic);
        vec3 radiance = u_LightColor[i] * u_LightIntensity[i];

        direct += (kd * albedo.rgb / PI + specular) * radiance * ndl * attenuation;
    }

    // ---- Ambient: IBL or hemisphere ----
    vec3 F = FresnelSchlickRoughness(ndv, f0, roughness);
    vec3 kd = (1.0 - F) * (1.0 - metallic);
    vec3 reflectDir = reflect(-view, n);

    vec2 brdf = texture(u_BRDFLut, vec2(ndv, roughness)).rg;

    vec3 diffuseLight;
    vec3 specularLight;

    if (u_HasIBL != 0)
    {
        diffuseLight = texture(u_Irradiance, u_EnvRotation * n).rgb;

        const float MAX_REFLECTION_LOD = 4.0;
        specularLight = textureLod(u_Prefiltered, u_EnvRotation * reflectDir,
                                   roughness * MAX_REFLECTION_LOD).rgb;
    }
    else
    {
        diffuseLight = HemisphereAmbient(n);
        specularLight = mix(HemisphereAmbient(reflectDir), diffuseLight, roughness);
    }

    // Multi-scattering energy compensation (Fdez-Aguera): rough metals
    // keep the energy single-scatter GGX loses.
    float energy = max(brdf.x + brdf.y, 1e-3);
    vec3 energyCompensation = 1.0 + f0 * (1.0 / energy - 1.0);

    vec3 specularIBL = specularLight * (F * brdf.x + brdf.y) * energyCompensation;

    // Specular occlusion from AO (Lagarde).
    float specularAO = clamp(pow(ndv + ao, exp2(-16.0 * roughness - 1.0)) - 1.0 + ao, 0.0, 1.0);

    vec3 ambient = (kd * diffuseLight * albedo.rgb * ao + specularIBL * specularAO) *
                   u_EnvironmentIntensity;

    // ---- Flat ambient term (on top of the environment) ----
    vec3 ambientFallback = u_AmbientColor * albedo.rgb * ao;

    vec3 color = ambientFallback + direct + ambient + emissive;

    FragColor = vec4(color, alpha);
}
