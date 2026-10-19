/*
    MSAA.fx — iterative directional anti-aliasing.

    A post-process (image-space) filter, not hardware multisampling. Every pass
    measures the luminance spread around each pixel and blends the pixels that
    sit on an edge along the edge's own direction, where the staircase steps
    are. The technique runs the pass eight times, so one application only has
    to soften an edge a little; repeating it converges on a smooth ramp with no
    long per-pixel searches.

    Each pass costs five texture reads on flat pixels (most of the screen, and
    they stay untouched) and the same on edges, so eight passes stay cheaper
    than one pass of the search-based version this replaces.
*/

#include "ReShade.fxh"

uniform float EdgeThreshold <
    ui_label = "Edge threshold";
    ui_type = "slider";
    ui_min = 0.02; ui_max = 0.50; ui_step = 0.01;
    ui_tooltip =
        "Minimum luminance spread that counts as an edge.\n"
        "Lower catches softer edges and some texture detail; higher stays\n"
        "conservative and leaves more aliasing. 0.10 is a good default.";
> = 0.10;

uniform float BlendStrength <
    ui_label = "Blend strength";
    ui_type = "slider";
    ui_min = 0.05; ui_max = 1.00; ui_step = 0.01;
    ui_tooltip =
        "How much of the smoothed colour each pass mixes in.\n"
        "With the pass repeating eight times, low values are safe: 0.35\n"
        "converges to near-full blending. Higher is faster but blunter.";
> = 0.35;

float MSAALuma(float3 color)
{
    return dot(color, float3(0.299, 0.587, 0.114));
}

// One directional pass. Flat neighbourhoods cost five reads and come back
// unchanged; edges blend towards the pixels along the edge direction.
float3 MSAASmooth(float3 center, float2 texcoord)
{
    const float2 px = ReShade::PixelSize;

    const float3 north = tex2D(ReShade::BackBuffer, texcoord + float2( 0.0, -1.0) * px).rgb;
    const float3 south = tex2D(ReShade::BackBuffer, texcoord + float2( 0.0,  1.0) * px).rgb;
    const float3 west  = tex2D(ReShade::BackBuffer, texcoord + float2(-1.0,  0.0) * px).rgb;
    const float3 east  = tex2D(ReShade::BackBuffer, texcoord + float2( 1.0,  0.0) * px).rgb;

    const float lumaCenter = MSAALuma(center);
    const float lumaNorth = MSAALuma(north);
    const float lumaSouth = MSAALuma(south);
    const float lumaWest = MSAALuma(west);
    const float lumaEast = MSAALuma(east);

    const float lumaMin = min(lumaCenter, min(min(lumaNorth, lumaSouth), min(lumaWest, lumaEast)));
    const float lumaMax = max(lumaCenter, max(max(lumaNorth, lumaSouth), max(lumaWest, lumaEast)));
    const float spread = lumaMax - lumaMin;

    if (spread <= EdgeThreshold)
        return center;

    // the axis the luma changes along tells the way the edge runs, and the
    // blend has to follow the edge: a vertical edge is smoothed with the
    // pixels above and below it, not with the ones that jump across it
    const float changeX = abs(lumaWest - lumaCenter) + abs(lumaEast - lumaCenter);
    const float changeY = abs(lumaNorth - lumaCenter) + abs(lumaSouth - lumaCenter);

    const float3 along = (changeX > changeY) ? 0.5 * (north + south)
                                             : 0.5 * (west + east);

    // fade the blend in with the contrast, so a pixel only just over the
    // threshold moves a little instead of snapping to the neighbour average
    const float ramp = saturate((spread - EdgeThreshold) / EdgeThreshold);
    return lerp(center, along, BlendStrength * ramp);
}

float3 PS_MSAA(float4 position : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    return MSAASmooth(tex2D(ReShade::BackBuffer, texcoord).rgb, texcoord);
}

technique MSAA <
    ui_label = "MSAA (post-process)";
    ui_tooltip =
        "Image-space anti-aliasing in eight passes. Each pass measures the\n"
        "luminance spread around every pixel and blends edges along their own\n"
        "direction, so staircases soften while flat areas cost nothing.\n"
        "Raise the threshold to catch more edges; raise the strength for a\n"
        "blunter, faster result.";
>
{
    pass { VertexShader = PostProcessVS; PixelShader = PS_MSAA; }
    pass { VertexShader = PostProcessVS; PixelShader = PS_MSAA; }
    pass { VertexShader = PostProcessVS; PixelShader = PS_MSAA; }
    pass { VertexShader = PostProcessVS; PixelShader = PS_MSAA; }
    pass { VertexShader = PostProcessVS; PixelShader = PS_MSAA; }
    pass { VertexShader = PostProcessVS; PixelShader = PS_MSAA; }
    pass { VertexShader = PostProcessVS; PixelShader = PS_MSAA; }
    pass { VertexShader = PostProcessVS; PixelShader = PS_MSAA; }
}
