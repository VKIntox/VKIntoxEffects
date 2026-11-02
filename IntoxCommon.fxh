/*
    IntoxCommon.fxh - helpers for VKIntox's built-in effects
*/

#pragma once

namespace Intox
{
    uniform float FRAME_TIME < source = "frametime"; >;
    uniform int FRAME_COUNT < source = "framecount"; >;

    static const float2 ASPECT_RATIO = float2(1.0, BUFFER_WIDTH * BUFFER_RCP_HEIGHT);
    static const float2 PIXEL_SIZE = float2(BUFFER_RCP_WIDTH, BUFFER_RCP_HEIGHT);
    static const float2 SCREEN_SIZE = float2(BUFFER_WIDTH, BUFFER_HEIGHT);

    sampler sBackBufferTex { Texture = ReShade::BackBufferTex; };
    sampler sDepthBufferTex { Texture = ReShade::DepthBufferTex; };

    float2 depthtex_uv(float2 uv)
    {
#if RESHADE_DEPTH_INPUT_IS_UPSIDE_DOWN
        uv.y = 1.0 - uv.y;
#endif
        uv.x /= RESHADE_DEPTH_INPUT_X_SCALE;
        uv.y /= RESHADE_DEPTH_INPUT_Y_SCALE;
#if RESHADE_DEPTH_INPUT_X_PIXEL_OFFSET
        uv.x -= RESHADE_DEPTH_INPUT_X_PIXEL_OFFSET * BUFFER_RCP_WIDTH;
#else
        uv.x -= RESHADE_DEPTH_INPUT_X_OFFSET / 2.000000001;
#endif
#if RESHADE_DEPTH_INPUT_Y_PIXEL_OFFSET
        uv.y += RESHADE_DEPTH_INPUT_Y_PIXEL_OFFSET * BUFFER_RCP_HEIGHT;
#else
        uv.y += RESHADE_DEPTH_INPUT_Y_OFFSET / 2.000000001;
#endif
        return uv;
    }

    float get_depth(float2 uv)
    {
        float depth = tex2Dlod(sDepthBufferTex, float4(depthtex_uv(uv), 0, 0)).x;
        return depth;
    }

    float linearize_depth(float depth)
    {
        depth *= RESHADE_DEPTH_MULTIPLIER;
#if RESHADE_DEPTH_INPUT_IS_LOGARITHMIC
        const float C = 0.01;
        depth = (exp(depth * log(C + 1.0)) - 1.0) / C;
#endif
#if RESHADE_DEPTH_INPUT_IS_REVERSED
        depth = 1.0 - depth;
#endif
        const float N = 1.0;
        depth /= RESHADE_DEPTH_LINEARIZATION_FAR_PLANE - depth * (RESHADE_DEPTH_LINEARIZATION_FAR_PLANE - N);

        return saturate(depth);
    }

    float linear_depth(float2 uv)
    {
        float depth = get_depth(uv);
        depth = linearize_depth(depth);
        return depth;
    }
}

float IntoxFovTanHalf()
{
    return tan(radians(90.0 * 0.5));
}

float3 IntoxViewPosition(float2 texcoord, float linearDepth)
{
    const float tanHalfX = IntoxFovTanHalf();
    const float tanHalfY = tanHalfX / Intox::ASPECT_RATIO.y;
    const float2 dir = float2(texcoord.x * 2.0 - 1.0, 1.0 - texcoord.y * 2.0) * float2(tanHalfX, tanHalfY);
    const float viewDepth = RESHADE_DEPTH_LINEARIZATION_FAR_PLANE * linearDepth;
    return float3(dir * viewDepth, viewDepth);
}

float2 IntoxUvFromPosition(float3 position)
{
    const float tanHalfX = IntoxFovTanHalf();
    const float tanHalfY = tanHalfX / Intox::ASPECT_RATIO.y;
    return float2((position.x / (position.z * tanHalfX) + 1.0) * 0.5,
                  (1.0 - position.y / (position.z * tanHalfY)) * 0.5);
}

float3 IntoxViewNormal(float2 texcoord, float3 basePos)
{
    const float2 px = Intox::PIXEL_SIZE;
    const float3 right = IntoxViewPosition(texcoord + float2(px.x, 0.0),
                                           Intox::linear_depth(texcoord + float2(px.x, 0.0)));
    const float3 up = IntoxViewPosition(texcoord + float2(0.0, px.y),
                                        Intox::linear_depth(texcoord + float2(0.0, px.y)));

    const float3 normal = normalize(cross(right - basePos, up - basePos));
    const float3 toCamera = -normalize(basePos);

    return dot(normal, toCamera) < 0.0 ? -normal : normal;
}
