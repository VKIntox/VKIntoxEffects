/*
    IntoxRimlight.fx - Rimlights
*/

#include "ReShade.fxh"
#include "IntoxCommon.fxh"

uniform float IntoxRimLightStrength <
    ui_label = "Strength";
    ui_type = "slider";
    ui_min = 0.0; ui_max = 4.0; ui_step = 0.01;
    ui_category = "Intox rim light";
    ui_tooltip = "Overall brightness of the rim. 0 disables the effect.";
> = 1.0;

uniform float3 IntoxRimLightColor <
    ui_label = "Rim colour";
    ui_type = "color";
    ui_category = "Intox rim light";
    ui_tooltip = "The light's colour. Subtle amber reads as sunlight; cyan and magenta read as neon.";
> = float3(1.00, 0.97, 0.90);

uniform float IntoxRimLightFalloff <
    ui_label = "Falloff";
    ui_type = "slider";
    ui_min = 0.20; ui_max = 8.00; ui_step = 0.01;
    ui_category = "Intox rim light";
    ui_tooltip =
        "How tightly the rim hugs the silhouette. Low values halo everything\n"
        "broadly; high values reduce it to a hairline edge.";
> = 2.5;

uniform float IntoxRimLightDepthGate <
    ui_label = "Depth contrast gate";
    ui_type = "slider";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
    ui_category = "Intox rim light";
    ui_tooltip =
        "How much closer a pixel must be to its background before it earns a\n"
        "rim. 0 lights every normal-driven edge, including flat interior\n"
        "detail; 0.1 and past picks only true foreground silhouettes.";
> = 0.08;

uniform float IntoxRimLightSpread <
    ui_label = "Silhouette look-ahead";
    ui_type = "slider";
    ui_min = 1.0; ui_max = 4.0; ui_step = 1.0;
    ui_category = "Intox rim light";
    ui_tooltip =
        "How many pixels outward the depth gate probes for the background.\n"
        "1 traces crisp edges; 3 lets slightly blurred or anti-aliased\n"
        "silhouettes still hold a rim.";
> = 2.0;

uniform float IntoxRimLightLumaGate <
    ui_label = "Highlight restraint";
    ui_type = "slider";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
    ui_category = "Intox rim light";
    ui_tooltip =
        "Dims the rim on already bright pixels so glowing game elements and\n"
        "the sky don't double up. 0 adds the rim everywhere, untouched.";
> = 0.5;

uniform float IntoxRimLightSkyDepth <
    ui_label = "Sky cutoff";
    ui_type = "slider";
    ui_min = 0.9000; ui_max = 1.0000; ui_step = 0.0001;
    ui_category = "Intox rim light";
    ui_tooltip = "Linear depth beyond which pixels count as sky and stay untouched.";
> = 0.9999;

float3 PS_IntoxRimlight(float4 position : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    const float3 color = tex2D(ReShade::BackBuffer, texcoord).rgb;
    const float linNear = Intox::linear_depth(texcoord);

    if (linNear >= IntoxRimLightSkyDepth || linNear >= 1.0)
        return color;

    const float3 basePos = IntoxViewPosition(texcoord, linNear);
    const float3 normal = IntoxViewNormal(texcoord, basePos);
    const float3 toCamera = -normalize(basePos);

    float rim = saturate(1.0 - dot(normal, toCamera));
    rim = pow(rim, IntoxRimLightFalloff);

    if (rim <= 0.002)
        return color;

    if (IntoxRimLightDepthGate > 0.0)
    {
        const float2 px = float2(BUFFER_RCP_WIDTH, BUFFER_RCP_HEIGHT);
        const float reach = IntoxRimLightSpread;
        float background = linNear;

        for (int i = 1; i <= int(reach); ++i)
        {
            background = max(background, Intox::linear_depth(texcoord + float2( i,  0) * px));
            background = max(background, Intox::linear_depth(texcoord + float2(-i,  0) * px));
            background = max(background, Intox::linear_depth(texcoord + float2( 0,  i) * px));
            background = max(background, Intox::linear_depth(texcoord + float2( 0, -i) * px));
        }

        const float contrast = saturate(background - linNear);
        rim *= saturate((contrast - IntoxRimLightDepthGate * 0.10) * 12.0);

        if (rim <= 0.002)
            return color;
    }

    const float3 rimColor = IntoxRimLightColor * rim * IntoxRimLightStrength;

    const float luma = dot(color, float3(0.2126, 0.7152, 0.0722));
    const float restraint = lerp(1.0, saturate(1.0 - luma), IntoxRimLightLumaGate);

    return saturate(color + rimColor * restraint);
}

technique IntoxRimlight <
    ui_label = "Intox rim light";
    ui_tooltip =
        "Back-lights the edges of foreground objects with a chosen colour,\n"
        "reconstructing normals from the depth buffer. Falloff shapes the\n"
        "halo, the depth gate keeps interior detail quiet.";
>
{
    pass
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_IntoxRimlight;
    }
}
