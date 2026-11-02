/*
    IntoxSSR.fx - screen-space reflections. Inspired by qUINT's SSR.
*/

uniform float SSR_FOV <
    ui_type = "drag";
    ui_min = 0.00; ui_max = 100.00;
    ui_label = "Vertical field of view";
    ui_tooltip = "Vertical field of view, ideally matching the game camera.\n"
                 "Depth linearization is rarely exact, so the value that looks\n"
                 "right can differ from the real one; tune it until reflected\n"
                 "geometry lines up with what it mirrors.";
    ui_category = "Global";
> = 50.0;

uniform float SSR_REFLECTION_STRENGTH <
    ui_type = "drag";
    ui_min = 0.00; ui_max = 1.00;
    ui_label = "Reflection strength";
    ui_tooltip = "How much of the reflected colour is mixed into the scene.";
    ui_category = "Global";
> = 1.0;

uniform float SSR_FRESNEL_POWER <
    ui_type = "drag";
    ui_min = 1.00; ui_max = 10.00;
    ui_label = "Reflection exponent";
    ui_tooltip = "Power of the angle falloff in the Schlick approximation.\n"
                 "Higher values confine reflections to surfaces seen at very\n"
                 "shallow angles. Schlick's classic value is 5. The Fresnel\n"
                 "coefficient stays at 0, which suits most surfaces.";
    ui_category = "Global";
> = 5.0;

uniform float SSR_FADE_DISTANCE <
    ui_type = "drag";
    ui_min = 0.001; ui_max = 1.00;
    ui_label = "Fade distance";
    ui_tooltip = "Distance at which reflections disappear completely.\n"
                 "1 means no distance fade at all.";
    ui_category = "Global";
> = 0.8;

uniform float SSR_RAY_GROWTH <
    ui_type = "drag";
    ui_min = 1.01; ui_max = 3.00;
    ui_label = "Ray growth";
    ui_tooltip = "How quickly the ray step grows along the march.\n"
                 "1 keeps every step the same length, 2 doubles it each\n"
                 "iteration. Raise it when distant geometry is missed, at the\n"
                 "cost of precision.";
    ui_category = "Ray Tracing";
> = 1.6;

uniform float SSR_ACCEPT_TOLERANCE <
    ui_type = "drag";
    ui_min = 0.0; ui_max = 12.00;
    ui_label = "Acceptance tolerance";
    ui_tooltip = "Depth error still accepted as an intersection. Larger values\n"
                 "give smoother but less accurate reflections.";
    ui_category = "Ray Tracing";
> = 2.5;

uniform float SSR_JITTER <
    ui_type = "drag";
    ui_min = 0.0; ui_max = 1.00;
    ui_label = "Ray jitter";
    ui_tooltip = "Randomizes the step length per pixel. This trades noise for\n"
                 "coherence; the noise is what the spatial filter removes.";
    ui_category = "Ray Tracing";
> = 0.25;

uniform float SSR_FILTER_RADIUS <
    ui_type = "drag";
    ui_min = 0.0; ui_max = 5.00;
    ui_label = "Filter radius";
    ui_tooltip = "Size of the spatial filter kernel. Larger values blur the\n"
                 "reflection more and lose fine detail.";
    ui_category = "Filtering and Details";
> = 0.5;

uniform float SSR_RELIEF_STRENGTH <
    ui_type = "drag";
    ui_min = 0.0; ui_max = 1.00;
    ui_label = "Surface relief strength";
    ui_tooltip = "Strength of the embossed texture relief. Higher values make\n"
                 "surfaces look bumpier.";
    ui_category = "Filtering and Details";
> = 0.05;

uniform float SSR_RELIEF_SIZE <
    ui_type = "drag";
    ui_min = 0.1; ui_max = 1.00;
    ui_label = "Surface relief size";
    ui_tooltip = "Scale of the embossed relief. Lower values keep more high\n"
                 "frequency detail in the bump pattern.";
    ui_category = "Filtering and Details";
> = 0.35;

#include "ReShade.fxh"
#include "IntoxCommon.fxh"

texture2D SSR_ColorTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
sampler2D sSSR_ColorTex { Texture = SSR_ColorTex; AddressU = MIRROR; };

texture2D CommonTex0 { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
sampler2D sCommonTex0 { Texture = CommonTex0; };

texture2D CommonTex1 { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
sampler2D sCommonTex1 { Texture = CommonTex1; };

struct SSRVertOut
{
    float4 vpos : SV_Position;
    float2 uv : TEXCOORD0;
    float3 uvtoviewADD : TEXCOORD4;
    float3 uvtoviewMUL : TEXCOORD5;
};

struct SSRRay
{
    float3 origin;
    float3 dir;
    float step;
    float3 pos;
};

struct SSRScene
{
    float3 eyedir;
    float3 normal;
    float3 position;
    float depth;
};

struct SSRTrace
{
    int num_steps;
    int num_refines;
    float2 uv;
    float3 error;
    bool hit;
};

struct SSRBlurData
{
    float4 key;
    float4 mask;
};

SSRVertOut VS_SSR(in uint id : SV_VertexID)
{
    SSRVertOut o;
    o.uv.x = (id == 2) ? 2.0 : 0.0;
    o.uv.y = (id == 1) ? 2.0 : 0.0;
    o.vpos = float4(o.uv.xy * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);

    o.uvtoviewADD = float3(-tan(radians(SSR_FOV * 0.5)).xx, 1.0) * Intox::ASPECT_RATIO.yxx;
    o.uvtoviewMUL = float3(-2.0 * o.uvtoviewADD.xy, 0.0);

    return o;
}

float3 SSRViewPosition(in float2 uv, in SSRVertOut i)
{
    return (uv.xyx * i.uvtoviewMUL + i.uvtoviewADD) * Intox::linear_depth(uv) * RESHADE_DEPTH_LINEARIZATION_FAR_PLANE;
}

float2 SSRScreenUv(in float3 pos, in SSRVertOut i)
{
    return pos.xy / (i.uvtoviewMUL.xy * pos.z) - i.uvtoviewADD.xy / i.uvtoviewMUL.xy;
}

float4 SSRDepthNormal(in SSRVertOut i)
{
    float3 single_pixel_offset = float3(Intox::PIXEL_SIZE, 0);

    float3 position = SSRViewPosition(i.uv, i);
    float3 position_delta_x1 = -position + SSRViewPosition(i.uv + single_pixel_offset.xz, i);
    float3 position_delta_x2 = position - SSRViewPosition(i.uv - single_pixel_offset.xz, i);
    float3 position_delta_y1 = -position + SSRViewPosition(i.uv + single_pixel_offset.zy, i);
    float3 position_delta_y2 = position - SSRViewPosition(i.uv - single_pixel_offset.zy, i);

    position_delta_x1 = lerp(position_delta_x1, position_delta_x2, abs(position_delta_x1.z) > abs(position_delta_x2.z));
    position_delta_y1 = lerp(position_delta_y1, position_delta_y2, abs(position_delta_y1.z) > abs(position_delta_y2.z));

    float deltaz = abs(position_delta_x1.z * position_delta_x1.z - position_delta_x2.z * position_delta_x2.z)
                 + abs(position_delta_y1.z * position_delta_y1.z - position_delta_y2.z * position_delta_y2.z);

    return float4(normalize(cross(position_delta_y1, position_delta_x1)), deltaz);
}

float3 SSRReliefNormal(float2 uv, float2 offset, float scale, float sharpness)
{
    float3 offset_swiz = float3(offset.xy, 0);
    float hpx = dot(tex2Dlod(Intox::sBackBufferTex, float4(uv + offset_swiz.xz, 0, 0)).xyz, 0.333) * scale;
    float hmx = dot(tex2Dlod(Intox::sBackBufferTex, float4(uv - offset_swiz.xz, 0, 0)).xyz, 0.333) * scale;
    float hpy = dot(tex2Dlod(Intox::sBackBufferTex, float4(uv + offset_swiz.zy, 0, 0)).xyz, 0.333) * scale;
    float hmy = dot(tex2Dlod(Intox::sBackBufferTex, float4(uv - offset_swiz.zy, 0, 0)).xyz, 0.333) * scale;

    float dpx = Intox::linear_depth(uv + offset_swiz.xz);
    float dmx = Intox::linear_depth(uv - offset_swiz.xz);
    float dpy = Intox::linear_depth(uv + offset_swiz.zy);
    float dmy = Intox::linear_depth(uv - offset_swiz.zy);

    float2 xymult = float2(abs(dmx - dpx), abs(dmy - dpy)) * sharpness;
    xymult = saturate(1.0 - xymult);

    float3 normal;
    normal.xy = float2(hmx - hpx, hmy - hpy) * xymult / offset.xy * 0.5;
    normal.z = 1.0;

    return normalize(normal);
}

float3 SSRBlendNormals(float3 n1, float3 n2)
{
    n1 += float3(0, 0, 1);
    n2 *= float3(-1, -1, 1);
    return n1 * dot(n1, n2) / n1.z - n2;
}

float SSRBayer(float2 vpos, int max_level)
{
    float finalBayer = 0.0;
    float finalDivisor = 0.0;
    float layerMult = 1.0;

    for (float bayerLevel = max_level; bayerLevel >= 1.0; bayerLevel--)
    {
        layerMult *= 4.0;

        float2 bayercoord = floor(vpos.xy * exp2(1 - bayerLevel)) % 2;
        float line0202 = bayercoord.x * 2.0;

        finalBayer += lerp(line0202, 3.0 - line0202, bayercoord.y) / 3.0 * layerMult;
        finalDivisor += layerMult;
    }

    return finalBayer / finalDivisor;
}

void PS_CopyScene(in SSRVertOut i, out float4 o : SV_Target0)
{
    o = tex2D(Intox::sBackBufferTex, i.uv);
}

void PS_Reflect(in SSRVertOut i, out float4 reflection : SV_Target0, out float4 blurbuffer : SV_Target1)
{
    blurbuffer = SSRDepthNormal(i);
    float jitter = SSRBayer(i.vpos.xy, 3) - 0.5;

    SSRScene scene;
    scene.position = SSRViewPosition(i.uv, i);
    scene.eyedir = normalize(scene.position);
    scene.normal = SSRBlendNormals(blurbuffer.xyz, SSRReliefNormal(i.uv, 40.0 * Intox::PIXEL_SIZE / scene.position.z * SSR_RELIEF_SIZE, 0.005 * SSR_RELIEF_STRENGTH, 1000.0));
    scene.depth = scene.position.z / RESHADE_DEPTH_LINEARIZATION_FAR_PLANE;

    SSRRay ray;
    ray.origin = scene.position;
    ray.dir = reflect(scene.eyedir, scene.normal);
    ray.step = (0.2 + 0.05 * jitter * SSR_JITTER) * sqrt(scene.depth) * rcp(1e-3 + saturate(1 - dot(ray.dir, scene.eyedir)));
    ray.pos = ray.origin + ray.dir * ray.step;

    SSRTrace trace;
    trace.uv = i.uv;
    trace.hit = 0;
    trace.num_steps = 20;
    trace.num_refines = 3;

    int j = 0;
    int k = 0;
    bool uv_inside_screen;

    while (j++ < trace.num_steps)
    {
        trace.uv = SSRScreenUv(ray.pos, i);
        trace.error = SSRViewPosition(trace.uv, i) - ray.pos;

        if (trace.error.z < 0 && trace.error.z > -SSR_ACCEPT_TOLERANCE * ray.step)
        {
            j = 0;

            if (k < trace.num_refines)
            {
                ray.step /= SSR_RAY_GROWTH;
                ray.pos -= ray.dir * ray.step;
                ray.step *= SSR_RAY_GROWTH * rcp(trace.num_steps);
            }
            else
            {
                j += trace.num_steps;
            }
            k++;
        }

        ray.pos += ray.dir * ray.step;
        ray.step *= SSR_RAY_GROWTH;

        uv_inside_screen = all(saturate(-trace.uv.y * trace.uv.y + trace.uv.y));
        j += trace.num_steps * !uv_inside_screen;
    }

    trace.hit = k != 0;

    float fresnel_k = 0.04;
    float schlick = lerp(fresnel_k, 1, pow(saturate(1 - dot(-scene.eyedir, scene.normal)), SSR_FRESNEL_POWER)) * SSR_REFLECTION_STRENGTH;
    float fade = saturate(dot(scene.eyedir, ray.dir)) * saturate(1 - dot(-scene.eyedir, scene.normal));

    reflection.a = trace.hit * schlick * fade;
    reflection.rgb = tex2D(sSSR_ColorTex, trace.uv).rgb * reflection.a;

    blurbuffer.xyz = blurbuffer.xyz * 0.5 + 0.5;
}

void SSRBlurFetch(inout SSRBlurData o, in sampler inputsampler, in float4 uv)
{
    o.key = tex2Dlod(inputsampler, uv);
    o.mask = tex2Dlod(sCommonTex1, uv);
    o.mask.xyz = o.mask.xyz * 2 - 1;
}

float SSRBlurWeight(in SSRBlurData center, in SSRBlurData tap)
{
    float depth_term = saturate(1 - abs(tap.mask.w - center.mask.w) * 50);
    float normal_term = saturate(dot(tap.mask.xyz, center.mask.xyz) * 50 - 49);
    return depth_term * normal_term;
}

float4 SSRBlur(in SSRVertOut i, in sampler inputsampler, in float radius, in float2 axis)
{
    float4 blur_uv = float4(i.uv.xy, 0, 0);

    SSRBlurData center, tap;
    SSRBlurFetch(center, inputsampler, blur_uv);

    if (SSR_FILTER_RADIUS == 0) return center.key;

    float kernel_size = radius;
    float k = -2.0 * rcp(kernel_size * kernel_size + 1e-3);

    float4 blursum = 0;
    float4 blursum_noweight = 0;
    float blursum_weight = 1e-3;
    float blursum_noweight_weight = 1e-3;

    [loop]
    for (float j = -floor(kernel_size); j <= floor(kernel_size); j++)
    {
        SSRBlurFetch(tap, inputsampler, float4(i.uv + axis * (2.0 * j - 0.5), 0, 0));
        float tap_weight = SSRBlurWeight(center, tap);

        blursum += tap.key * tap_weight * exp(j * j * k) * tap.key.w;
        blursum_weight += tap_weight * exp(j * j * k) * tap.key.w;
        blursum_noweight += tap.key * exp(j * j * k) * tap.key.w;
        blursum_noweight_weight += exp(j * j * k) * tap.key.w;
    }

    blursum /= blursum_weight;
    blursum_noweight /= blursum_noweight_weight;

    return lerp(center.key, blursum, saturate(blursum_weight * 2));
}

void PS_FilterHorizontal(in SSRVertOut i, out float4 o : SV_Target0)
{
    o = SSRBlur(i, sCommonTex0, SSR_FILTER_RADIUS, float2(0, 1) * Intox::PIXEL_SIZE);
}

void PS_FilterVertical(in SSRVertOut i, out float4 o : SV_Target0)
{
    float4 reflection = SSRBlur(i, sSSR_ColorTex, SSR_FILTER_RADIUS, float2(1, 0) * Intox::PIXEL_SIZE);
    float alpha = reflection.w;

    float fade = saturate(1 - Intox::linear_depth(i.uv) / SSR_FADE_DISTANCE);
    o = tex2D(Intox::sBackBufferTex, i.uv);

    o.rgb = lerp(o.rgb, reflection.rgb, alpha * fade);
}

technique IntoxSSR <
    ui_label = "Intox screen-space reflections";
    ui_tooltip =
        "Screen-space reflections built from the depth buffer and the colour\n"
        "buffer alone. The reflected ray is marched across the screen with a\n"
        "growing step, then refined on contact. Anything outside the frame or\n"
        "beyond the fade distance simply keeps its unreflected colour.";
>
{
    pass
    {
        VertexShader = VS_SSR;
        PixelShader = PS_CopyScene;
        RenderTarget = SSR_ColorTex;
    }
    pass
    {
        VertexShader = VS_SSR;
        PixelShader = PS_Reflect;
        RenderTarget0 = CommonTex0;
        RenderTarget1 = CommonTex1;
    }
    pass
    {
        VertexShader = VS_SSR;
        PixelShader = PS_FilterHorizontal;
        RenderTarget = SSR_ColorTex;
    }
    pass
    {
        VertexShader = VS_SSR;
        PixelShader = PS_FilterVertical;
    }
}
