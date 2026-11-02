/*
    IntoxMXAO.fx - ambient occlusion, inspired by qUINT's MXAO
*/

#ifndef MXAO_MIP_AO
    #define MXAO_MIP_AO 0
#endif

#ifndef MXAO_MIP_IL
    #define MXAO_MIP_IL 2
#endif

#ifndef MXAO_INDIRECT
    #define MXAO_INDIRECT 0
#endif

#ifndef MXAO_SMOOTH_NORMALS
    #define MXAO_SMOOTH_NORMALS 0
#endif

#ifndef MXAO_DUAL_LAYER
    #define MXAO_DUAL_LAYER 0
#endif

#ifndef MXAO_HIGH_QUALITY
    #define MXAO_HIGH_QUALITY 0
#endif

uniform int MXAO_SAMPLE_QUALITY <
    ui_type = "combo";
    ui_label = "Sample quality";
    ui_items = "Very Low (4 samples)\0Low (8 samples)\0Medium (16 samples)\0High (24 samples)\0Very High (32 samples)\0Ultra (64 samples)\0Maximum (255 samples)\0Auto (variable)\0";
    ui_tooltip = "Master quality control and the main cost knob. Larger sampling\n"
                 "radii usually need a higher setting.";
    ui_category = "Global";
> = 2;

uniform float MXAO_RADIUS <
    ui_type = "drag";
    ui_min = 0.5; ui_max = 20.0;
    ui_label = "Sample radius";
    ui_tooltip = "Radius the occlusion is sampled over. Larger values catch\n"
                 "broad shading and lose fine detail.";
    ui_category = "Global";
> = 2.5;

#if (MXAO_HIGH_QUALITY == 0)
    uniform float MXAO_NORMAL_BIAS <
        ui_type = "drag";
        ui_min = 0.0; ui_max = 0.8;
        ui_label = "Normal bias";
        ui_tooltip = "Bias of the occlusion cone. Raises the threshold that\n"
                     "keeps nearly parallel surfaces from shading themselves.";
        ui_category = "Global";
    > = 0.2;
#else
    #define MXAO_NORMAL_BIAS 0
#endif

uniform float MXAO_RENDER_SCALE <
    ui_type = "drag";
    ui_label = "Render size scale";
    ui_min = 0.50; ui_max = 1.00;
    ui_tooltip = "Resolution factor for the effect. Lower values cut the cost\n"
                 "substantially but soften the result.\n"
                 "1.0 computes at full resolution,\n"
                 "0.5 at half width and half height.";
    ui_category = "Global";
> = 1.0;

uniform float MXAO_AO_AMOUNT <
    ui_type = "drag";
    ui_min = 0.00; ui_max = 4.00;
    ui_label = "Ambient occlusion amount";
    ui_tooltip = "Intensity of the occlusion. Pushing it too far clips dark\n"
                 "areas to black.";
    ui_category = "Ambient Occlusion";
> = 1.00;

#if (MXAO_INDIRECT != 0)
uniform float MXAO_IL_AMOUNT <
    ui_type = "drag";
    ui_min = 0.00; ui_max = 12.00;
    ui_label = "Indirect lighting amount";
    ui_tooltip = "Intensity of the indirect light. Too much of it blows out\n"
                 "bright spots to white.";
    ui_category = "Indirect Lighting";
> = 4.00;

uniform float MXAO_IL_SATURATION <
    ui_type = "drag";
    ui_min = 0.00; ui_max = 3.00;
    ui_label = "Indirect lighting saturation";
    ui_tooltip = "Colour saturation of the indirect light.";
    ui_category = "Indirect Lighting";
> = 1.00;
#endif

#if (MXAO_DUAL_LAYER != 0)
    uniform float MXAO_FINE_RADIUS <
        ui_type = "drag";
        ui_min = 0.1; ui_max = 1.00;
        ui_label = "Fine AO scale";
        ui_tooltip = "Radius multiplier for the fine layer. At 0.5 the second\n"
                     "layer scans geometry at half the main radius.";
        ui_category = "Double Layer";
    > = 0.2;

    uniform float MXAO_FINE_AMOUNT <
        ui_type = "drag";
        ui_min = 0.00; ui_max = 1.00;
        ui_label = "Fine AO intensity multiplier";
        ui_tooltip = "Intensity of the small-scale occlusion and indirect light.";
        ui_category = "Double Layer";
    > = 1.0;

    uniform float MXAO_COARSE_AMOUNT <
        ui_type = "drag";
        ui_min = 0.00; ui_max = 1.00;
        ui_label = "Coarse AO intensity multiplier";
        ui_tooltip = "Intensity of the large-scale occlusion and indirect light.";
        ui_category = "Double Layer";
    > = 1.0;
#endif

uniform int MXAO_BLEND_MODE <
    ui_type = "slider";
    ui_min = 0; ui_max = 3;
    ui_label = "Blending mode";
    ui_tooltip = "How the occlusion and indirect light are merged with the\n"
                 "original colour.";
    ui_category = "Blending";
> = 0;

uniform float MXAO_FADE_START <
    ui_type = "drag";
    ui_label = "Fade out start";
    ui_min = 0.00; ui_max = 1.00;
    ui_tooltip = "Distance at which the fade begins. 0.0 is at the camera,\n"
                 "1.0 at the sky. Must stay below Fade Out End.";
    ui_category = "Blending";
> = 0.05;

uniform float MXAO_FADE_END <
    ui_type = "drag";
    ui_label = "Fade out end";
    ui_min = 0.00; ui_max = 1.00;
    ui_tooltip = "Distance at which the fade completes. 0.0 is at the camera,\n"
                 "1.0 at the sky. Must stay above Fade Out Start.";
    ui_category = "Blending";
> = 0.4;

uniform int MXAO_DEBUG_VIEW <
    ui_type = "combo";
    ui_label = "Enable debug view";
    ui_items = "None\0AO/IL channel\0Normal vectors\0";
    ui_tooltip = "Switches the output to a diagnostic channel.";
    ui_category = "Debug";
> = 0;

#include "ReShade.fxh"
#include "IntoxCommon.fxh"

texture2D MXAO_ColorTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; MipLevels = 3+MXAO_MIP_IL; };
texture2D MXAO_DepthTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R16F; MipLevels = 3+MXAO_MIP_AO; };
texture2D MXAO_NormalTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; MipLevels = 3+MXAO_MIP_IL; };

sampler2D sMXAO_ColorTex { Texture = MXAO_ColorTex; };
sampler2D sMXAO_DepthTex { Texture = MXAO_DepthTex; };
sampler2D sMXAO_NormalTex { Texture = MXAO_NormalTex; };

texture2D CommonTex0 { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
sampler2D sCommonTex0 { Texture = CommonTex0; };

texture2D CommonTex1 { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
sampler2D sCommonTex1 { Texture = CommonTex1; };

struct MXAOVertOut
{
    float4 vpos : SV_Position;
    float4 uv : TEXCOORD0;
    nointerpolation float samples : TEXCOORD1;
    nointerpolation float3 uvtoviewADD : TEXCOORD4;
    nointerpolation float3 uvtoviewMUL : TEXCOORD5;
};

struct MXAOBlurData
{
    float4 key;
    float4 mask;
};

MXAOVertOut VS_MXAO(in uint id : SV_VertexID)
{
    MXAOVertOut o;

    o.uv.x = (id == 2) ? 2.0 : 0.0;
    o.uv.y = (id == 1) ? 2.0 : 0.0;
    o.uv.zw = o.uv.xy / MXAO_RENDER_SCALE;
    o.vpos = float4(o.uv.xy * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);

    static const int sample_counts[8] = {4, 8, 16, 24, 32, 64, 255, 8};
    o.samples = sample_counts[MXAO_SAMPLE_QUALITY];

    o.uvtoviewADD = float3(-1.0, -1.0, 1.0);
    o.uvtoviewMUL = float3(2.0, 2.0, 0.0);

    return o;
}

float3 MXAOViewPosition(in float2 uv, in MXAOVertOut i)
{
    return (uv.xyx * i.uvtoviewMUL + i.uvtoviewADD) * Intox::linear_depth(uv) * RESHADE_DEPTH_LINEARIZATION_FAR_PLANE;
}

float3 MXAOViewPositionMip(in float2 uv, in MXAOVertOut i, in int miplevel)
{
    return (uv.xyx * i.uvtoviewMUL + i.uvtoviewADD) * tex2Dlod(sMXAO_DepthTex, float4(uv.xyx, miplevel)).x;
}

void MXAOBlurFetch(inout MXAOBlurData o, in sampler inputsampler, in float inputscale, in float4 uv)
{
    o.key = tex2Dlod(inputsampler, uv * inputscale);
    o.mask = tex2Dlod(sMXAO_NormalTex, uv);
    o.mask.xyz = o.mask.xyz * 2 - 1;
}

float MXAOBlurWeight(in MXAOBlurData center, in MXAOBlurData tap)
{
    float depth_term = saturate(1 - abs(tap.mask.w - center.mask.w));
    float normal_term = saturate(dot(tap.mask.xyz, center.mask.xyz) * 16 - 15);
    return depth_term * normal_term;
}

float4 MXAOBlur(in MXAOVertOut i, in sampler inputsampler, in float inputscale, in float radius, in int blursteps)
{
    float4 blur_uv = float4(i.uv.xy, 0, 0);

    MXAOBlurData center, tap;
    MXAOBlurFetch(center, inputsampler, inputscale, blur_uv);

    float4 blursum = center.key;
    float4 blursum_noweight = center.key;
    float blurweight = 1;

    static const float2 offsets[8] =
    {
        float2(1.5, 0.5), float2(-1.5, -0.5), float2(-0.5, 1.5), float2(0.5, -1.5),
        float2(1.5, 2.5), float2(-1.5, -2.5), float2(-2.5, 1.5), float2(2.5, -1.5)
    };

    float2 blur_offsetscale = Intox::PIXEL_SIZE / inputscale * radius;

    [unroll]
    for (int s = 0; s < blursteps; s++)
    {
        blur_uv.xy = i.uv.xy + offsets[s] * blur_offsetscale;
        MXAOBlurFetch(tap, inputsampler, inputscale, blur_uv);

        float tap_weight = MXAOBlurWeight(center, tap);

        blurweight += tap_weight;
#if (MXAO_INDIRECT != 0)
        blursum += tap.key * tap_weight;
        blursum_noweight += tap.key;
#else
        blursum.w += tap.key.w * tap_weight;
        blursum_noweight.w += tap.key.w;
#endif
    }

#if (MXAO_INDIRECT != 0)
    blursum /= blurweight;
    blursum_noweight /= 1 + blursteps;
#else
    blursum.w /= blurweight;
    blursum_noweight.w /= 1 + blursteps;
#endif

#if (MXAO_INDIRECT != 0)
    return lerp(blursum, blursum_noweight, blurweight < 2);
#else
    return lerp(blursum.w, blursum_noweight.w, blurweight < 2);
#endif
}

void MXAOSampleSetup(in MXAOVertOut i, in float scaled_depth, in float layer_id, out float scaled_radius, out float falloff_factor)
{
    scaled_radius = 0.25 * MXAO_RADIUS / (i.samples * (scaled_depth + 2.0));
    falloff_factor = -1.0 / (MXAO_RADIUS * MXAO_RADIUS);

#if (MXAO_DUAL_LAYER != 0)
    scaled_radius *= lerp(1.0, MXAO_FINE_RADIUS + 1e-6, layer_id);
    falloff_factor *= lerp(1.0, 1.0 / (MXAO_FINE_RADIUS * MXAO_FINE_RADIUS + 1e-6), layer_id);
#endif
}

void MXAOSmoothNormals(inout float3 normal, in float3 position, in MXAOVertOut i)
{
    float2 scaled_radius = 0.018 / position.z * Intox::ASPECT_RATIO;
    float3 neighbour_normal[4] = {normal, normal, normal, normal};

    [unroll]
    for (int dir_index = 0; dir_index < 4; dir_index++)
    {
        float2 direction;
        sincos(6.28318548 * 0.25 * dir_index, direction.y, direction.x);

        [unroll]
        for (int direction_step = 1; direction_step <= 5; direction_step++)
        {
            float search_radius = exp2(direction_step);
            float2 tap_uv = i.uv.zw + direction * search_radius * scaled_radius;

            float3 temp_normal = tex2Dlod(sMXAO_NormalTex, float4(tap_uv, 0, 0)).xyz * 2.0 - 1.0;
            float3 temp_position = MXAOViewPositionMip(tap_uv, i, 0);

            float3 position_delta = temp_position - position;
            float distance_weight = saturate(1.0 - dot(position_delta, position_delta) * 20.0 / search_radius);
            float normal_angle = dot(normal, temp_normal);
            float angle_weight = smoothstep(0.3, 0.98, normal_angle) * smoothstep(1.0, 0.98, normal_angle);

            float total_weight = saturate(3.0 * distance_weight * angle_weight / search_radius);

            neighbour_normal[dir_index] = lerp(neighbour_normal[dir_index], temp_normal, total_weight);
        }
    }

    normal = normalize(neighbour_normal[0] + neighbour_normal[1] + neighbour_normal[2] + neighbour_normal[3]);
}

void PS_SetupInputs(in MXAOVertOut i, out float4 color : SV_Target0, out float4 depth : SV_Target1, out float4 normal : SV_Target2)
{
    float3 single_pixel_offset = float3(Intox::PIXEL_SIZE.xy, 0);

    float3 position = MXAOViewPosition(i.uv.xy, i);
    float3 position_delta_x1 = -position + MXAOViewPosition(i.uv.xy + single_pixel_offset.xz, i);
    float3 position_delta_x2 = position - MXAOViewPosition(i.uv.xy - single_pixel_offset.xz, i);
    float3 position_delta_y1 = -position + MXAOViewPosition(i.uv.xy + single_pixel_offset.zy, i);
    float3 position_delta_y2 = position - MXAOViewPosition(i.uv.xy - single_pixel_offset.zy, i);

    position_delta_x1 = lerp(position_delta_x1, position_delta_x2, abs(position_delta_x1.z) > abs(position_delta_x2.z));
    position_delta_y1 = lerp(position_delta_y1, position_delta_y2, abs(position_delta_y1.z) > abs(position_delta_y2.z));

    float deltaz = abs(position_delta_x1.z * position_delta_x1.z - position_delta_x2.z * position_delta_x2.z)
                 + abs(position_delta_y1.z * position_delta_y1.z - position_delta_y2.z * position_delta_y2.z);

    normal = float4(normalize(cross(position_delta_y1, position_delta_x1)) * 0.5 + 0.5, deltaz);
    color = tex2D(Intox::sBackBufferTex, i.uv.xy);
    depth = Intox::linear_depth(i.uv.xy) * RESHADE_DEPTH_LINEARIZATION_FAR_PLANE;
}

void PS_MarkPixels(in MXAOVertOut i, out float4 color : SV_Target0)
{
    if (Intox::linear_depth(i.uv.zw) >= MXAO_FADE_END
        || 0.25 * 0.5 * MXAO_RADIUS / (tex2D(sMXAO_DepthTex, i.uv.zw).x + 2.0) * BUFFER_HEIGHT < 1.0
        || i.uv.z > 1.0
        || i.uv.w > 1.0)
        discard;

    color = 1.0;
}

void PS_Obscurance(in MXAOVertOut i, out float4 color : SV_Target0)
{
    float3 position = MXAOViewPositionMip(i.uv.zw, i, 0);
    float3 normal = tex2D(sMXAO_NormalTex, i.uv.zw).xyz * 2.0 - 1.0;

    float sample_jitter = dot(floor(i.vpos.xy % 4 + 0.1), float2(0.0625, 0.25)) + 0.0625;

    float layer_id = (i.vpos.x + i.vpos.y) % 2.0;

#if (MXAO_SMOOTH_NORMALS != 0)
    MXAOSmoothNormals(normal, position, i);
#endif

    float scene_depth = position.z / RESHADE_DEPTH_LINEARIZATION_FAR_PLANE;
    position += normal * scene_depth;

    if (MXAO_SAMPLE_QUALITY == 7) i.samples = 2 + floor(0.05 * MXAO_RADIUS / scene_depth);

    float scaled_radius;
    float falloff_factor;
    MXAOSampleSetup(i, position.z, layer_id, scaled_radius, falloff_factor);

    float2 tap_uv, sample_dir;
    sincos(2.3999632 * 16 * sample_jitter, sample_dir.x, sample_dir.y);
    sample_dir *= scaled_radius;

    color = 0.0;

    [loop]
    for (int s = 0; s < i.samples; s++)
    {
        tap_uv = i.uv.zw + sample_dir.xy * Intox::ASPECT_RATIO * (s + sample_jitter);
        sample_dir.xy = mul(sample_dir.xy, float2x2(0.76465, -0.64444, 0.64444, 0.76465));

        float sample_mip = saturate(scaled_radius * s * 20.0) * 3.0;

        float3 delta_v = -position + MXAOViewPositionMip(tap_uv, i, sample_mip + MXAO_MIP_AO);
        float v2 = dot(delta_v, delta_v);
        float vn = dot(delta_v, normal) * rsqrt(v2);

        float sample_ao = saturate(1.0 + falloff_factor * v2) * saturate(vn - MXAO_NORMAL_BIAS);
#if (MXAO_INDIRECT != 0)
        [branch]
        if (sample_ao > 0.1)
        {
            float3 sample_il = tex2Dlod(sMXAO_ColorTex, float4(tap_uv, 0, sample_mip + MXAO_MIP_IL)).xyz;
            float3 sample_normal = tex2Dlod(sMXAO_NormalTex, float4(tap_uv, 0, sample_mip + MXAO_MIP_IL)).xyz * 2.0 - 1.0;

            sample_il *= sample_ao;
            sample_il *= 0.5 + 0.5 * saturate(dot(sample_normal, -delta_v * v2));

            color += float4(sample_il, sample_ao);
        }
#else
        color.w += sample_ao;
#endif
    }

#if (MXAO_INDIRECT != 0)
    color = saturate(color / ((1.0 - MXAO_NORMAL_BIAS) * i.samples) * 2.0);
#else
    color = saturate(color.w / ((1.0 - MXAO_NORMAL_BIAS) * i.samples) * 2.0);
#endif
    color = sqrt(color);

#if (MXAO_DUAL_LAYER != 0)
    color *= lerp(MXAO_COARSE_AMOUNT, MXAO_FINE_AMOUNT, layer_id);
#endif
}

void PS_ObscuranceHQ(in MXAOVertOut i, out float4 color : SV_Target0)
{
    float3 position = MXAOViewPositionMip(i.uv.zw, i, 0);
    float3 normal = normalize(tex2D(sMXAO_NormalTex, i.uv.zw).xyz * 2.0 - 1.0);

#if (MXAO_SMOOTH_NORMALS != 0)
    MXAOSmoothNormals(normal, position, i);
#endif

    float3 viewdir = normalize(-position);

    int directions = 2 + floor(i.samples / 32) * 2;
    int stepshalf = i.samples / (directions * 2);

    float angle_correct = 1 - viewdir.z * viewdir.z;
    float scaled_radius = MXAO_RADIUS / position.z / stepshalf * RESHADE_DEPTH_LINEARIZATION_FAR_PLANE;
    float falloff_factor = 0.25 * rcp(MXAO_RADIUS * MXAO_RADIUS);

    float sample_jitter = dot(floor(i.vpos.xy % 4 + 0.1), float2(0.0625, 0.25)) + 0.0625;

    float dir_phi = 3.14159265 / directions;
    float2 sample_dir;
    sincos(dir_phi * sample_jitter * 6, sample_dir.y, sample_dir.x);
    float2x2 rot_dir = float2x2(cos(dir_phi), -sin(dir_phi),
                                sin(dir_phi), cos(dir_phi));

    color = 0;

    [loop]
    for (float slice = 0; slice < directions; slice++)
    {
        sample_dir = mul(sample_dir, rot_dir);
        float2 start = sample_dir * sample_jitter;

        float3 sliceDir = float3(sample_dir, 0);
        float2 h = -1.0;

#if (MXAO_INDIRECT != 0)
        float3 il[2];
        il[0] = 0;
        il[1] = 0;
#endif
        [loop]
        for (int j = 0; j < stepshalf; j++)
        {
            float4 tap_uv = i.uv.zwzw + scaled_radius * Intox::PIXEL_SIZE.xyxy * start.xyxy * float4(1, 1, -1, -1);
            float sample_mip = saturate(scaled_radius * j * 0.01) * 3.0;

            float3 delta_v[2];
            delta_v[0] = -position + MXAOViewPositionMip(tap_uv.xy, i, sample_mip + MXAO_MIP_AO);
            delta_v[1] = -position + MXAOViewPositionMip(tap_uv.zw, i, sample_mip + MXAO_MIP_AO);

            float2 v2 = float2(dot(delta_v[0], delta_v[0]),
                               dot(delta_v[1], delta_v[1]));

            float2 inv_distance = rsqrt(v2);

            float2 sample_h = float2(dot(delta_v[0], viewdir),
                                     dot(delta_v[1], viewdir)) * inv_distance;

            float2 falloff = saturate(v2 * falloff_factor);
            sample_h = lerp(sample_h, h, falloff);

#if (MXAO_INDIRECT != 0)
            float3 sample_il[2], sample_normal[2];
            sample_il[0] = 0;
            sample_il[1] = 0;

            [branch]
            if (falloff.x < 0.8)
            {
                sample_il[0] = tex2Dlod(sMXAO_ColorTex, float4(tap_uv.xy, 0, sample_mip + MXAO_MIP_IL)).xyz;
                sample_normal[0] = tex2Dlod(sMXAO_NormalTex, float4(tap_uv.xy, 0, sample_mip + MXAO_MIP_IL)).xyz * 2.0 - 1.0;
                sample_il[0] *= saturate(-inv_distance.x * dot(delta_v[0], sample_normal[0]));
                sample_il[0] = lerp(sample_il[0], il[0], saturate(v2.x * falloff_factor));
            }
            [branch]
            if (falloff.y < 0.8)
            {
                sample_il[1] = tex2Dlod(sMXAO_ColorTex, float4(tap_uv.zw, 0, sample_mip + MXAO_MIP_IL)).xyz;
                sample_normal[1] = tex2Dlod(sMXAO_NormalTex, float4(tap_uv.zw, 0, sample_mip + MXAO_MIP_IL)).xyz * 2.0 - 1.0;
                sample_il[1] *= saturate(-inv_distance.y * dot(delta_v[1], sample_normal[1]));
                sample_il[1] = lerp(sample_il[1], il[1], saturate(v2.y * falloff_factor));
            }
#endif

            h.xy = (sample_h > h) ? sample_h : lerp(sample_h, h, 0.75);

#if (MXAO_INDIRECT != 0)
            il[0] = (sample_h.x > h.x) ? sample_il[0] : lerp(sample_il[0], il[0], 0.75);
            il[1] = (sample_h.y > h.y) ? sample_il[1] : lerp(sample_il[1], il[1], 0.75);
#endif
            start += sample_dir;
        }

        float3 normal_slice_plane = normalize(cross(sliceDir, viewdir));
        float3 tangent = cross(viewdir, normal_slice_plane);
        float3 proj_normal = normal - normal_slice_plane * dot(normal, normal_slice_plane);

        float proj_length = length(proj_normal);
        float cos_gamma = clamp(dot(proj_normal, viewdir) * rcp(proj_length), -1.0, 1.0);
        float gamma = -sign(dot(proj_normal, tangent)) * acos(cos_gamma);

        h = acos(min(h, 1));

        h.x = gamma + max(-h.x - gamma, -1.5707963);
        h.y = gamma + min(h.y - gamma, 1.5707963);

        h *= 2;

        float2 sample_ao = cos_gamma + h * sin(gamma) - cos(h - gamma);
        color.w += proj_length * dot(sample_ao, 0.25);
#if (MXAO_INDIRECT != 0)
        color.rgb += proj_length * sample_ao.x * 0.25 * il[0];
        color.rgb += proj_length * sample_ao.y * 0.25 * il[1];
#endif
    }

    color /= directions;
    color.w = 1 - color.w;
#if (MXAO_INDIRECT != 0)
    color = sqrt(color);
#else
    color = sqrt(color.w);
#endif
}

void PS_SpatialFilter1(in MXAOVertOut i, out float4 color : SV_Target0)
{
    color = MXAOBlur(i, sCommonTex0, MXAO_RENDER_SCALE, 0.75, 4);
}

void PS_SpatialFilter2(in MXAOVertOut i, out float4 color : SV_Target0)
{
    float4 ssil_ssao = MXAOBlur(i, sCommonTex1, 1, 1.0 / MXAO_RENDER_SCALE, 8);
    ssil_ssao *= ssil_ssao;
    color = tex2D(sMXAO_ColorTex, i.uv.xy);

    static const float3 lumcoeff = float3(0.2126, 0.7152, 0.0722);
    float scenedepth = Intox::linear_depth(i.uv.xy);
    float colorgray = dot(color.rgb, lumcoeff);
    float blendfact = 1.0 - colorgray;

#if (MXAO_INDIRECT != 0)
    ssil_ssao.xyz = lerp(dot(ssil_ssao.xyz, lumcoeff), ssil_ssao.xyz, MXAO_IL_SATURATION) * MXAO_IL_AMOUNT * 2.0;
#else
    ssil_ssao.xyz = 0.0;
#endif

#if (MXAO_HIGH_QUALITY == 0)
    ssil_ssao.w = 1.0 - pow(saturate(1.0 - ssil_ssao.w), MXAO_AO_AMOUNT * 2.0);
#else
    ssil_ssao.w = 1.0 - pow(saturate(1.0 - ssil_ssao.w), MXAO_AO_AMOUNT);
#endif
    ssil_ssao *= 1.0 - smoothstep(MXAO_FADE_START, MXAO_FADE_END, scenedepth * float4(2.0, 2.0, 2.0, 1.0));

    if (MXAO_BLEND_MODE == 0)
    {
        color.rgb -= (ssil_ssao.www - ssil_ssao.xyz) * blendfact * color.rgb;
    }
    else if (MXAO_BLEND_MODE == 1)
    {
        color.rgb = color.rgb * saturate(1.0 - ssil_ssao.www * blendfact * 1.2) + ssil_ssao.xyz * blendfact * colorgray * 2.0;
    }
    else if (MXAO_BLEND_MODE == 2)
    {
        float colordiff = saturate(2.0 * distance(normalize(color.rgb + 1e-6), normalize(ssil_ssao.rgb + 1e-6)));
        color.rgb = color.rgb + ssil_ssao.rgb * lerp(color.rgb, dot(color.rgb, 0.3333), colordiff) * blendfact * blendfact * 4.0;
        color.rgb = color.rgb * (1.0 - ssil_ssao.www * (1.0 - dot(color.rgb, lumcoeff)));
    }
    else if (MXAO_BLEND_MODE == 3)
    {
        color.rgb *= color.rgb;
        color.rgb -= (ssil_ssao.www - ssil_ssao.xyz) * color.rgb;
        color.rgb = sqrt(color.rgb);
    }

    if (MXAO_DEBUG_VIEW == 1)
    {
        color.rgb = max(0.0, 1.0 - ssil_ssao.www + ssil_ssao.xyz);
        color.rgb *= (MXAO_INDIRECT != 0) ? 0.5 : 1.0;
    }
    else if (MXAO_DEBUG_VIEW == 2)
    {
        color.rgb = tex2D(sMXAO_NormalTex, i.uv.xy).xyz;
        color.b = 1 - color.b;
    }

    color.a = 1.0;
}

technique IntoxMXAO <
    ui_label = "Intox ambient obscurance";
    ui_tooltip =
        "Neighbourhood occlusion computed over the depth buffer, with an\n"
        "optional indirect lighting pass that feeds surrounding colour back\n"
        "into the shade. Keep it near the top of the effect list. The\n"
        "preprocessor options expose additional modes and features.";
>
{
    pass
    {
        VertexShader = VS_MXAO;
        PixelShader = PS_SetupInputs;
        RenderTarget0 = MXAO_ColorTex;
        RenderTarget1 = MXAO_DepthTex;
        RenderTarget2 = MXAO_NormalTex;
    }
    pass
    {
        VertexShader = VS_MXAO;
        PixelShader = PS_MarkPixels;
        ClearRenderTargets = true;
        StencilEnable = true;
        StencilPass = REPLACE;
        StencilRef = 1;
    }
#if (MXAO_HIGH_QUALITY != 0)
    pass
    {
        VertexShader = VS_MXAO;
        PixelShader = PS_ObscuranceHQ;
        RenderTarget = CommonTex0;
        ClearRenderTargets = true;
        StencilEnable = true;
        StencilPass = KEEP;
        StencilFunc = EQUAL;
        StencilRef = 1;
    }
#else
    pass
    {
        VertexShader = VS_MXAO;
        PixelShader = PS_Obscurance;
        RenderTarget = CommonTex0;
        ClearRenderTargets = true;
        StencilEnable = true;
        StencilPass = KEEP;
        StencilFunc = EQUAL;
        StencilRef = 1;
    }
#endif
    pass
    {
        VertexShader = VS_MXAO;
        PixelShader = PS_SpatialFilter1;
        RenderTarget = CommonTex1;
    }
    pass
    {
        VertexShader = VS_MXAO;
        PixelShader = PS_SpatialFilter2;
    }
}
