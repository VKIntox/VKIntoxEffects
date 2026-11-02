/*
    IntoxDepthColorCorrection.fx - depth-based colour adjustments.
*/

#include "ReShade.fxh"
#include "IntoxCommon.fxh"

uniform float IntoxDCCTransition <
    ui_label = "Near band width";
    ui_type = "slider";
    ui_min = 0.01; ui_max = 1.00; ui_step = 0.01;
    ui_category = "Intox depth grader";
    ui_tooltip =
        "How much of the screen, in linearized depth, counts as the near\n"
        "band. 0.25 keeps most of the frame near-graded and leaves the last\n"
        "quarter to the far stack.";
> = 0.25;

uniform float IntoxDCCFarStart <
    ui_label = "Far band start";
    ui_type = "slider";
    ui_min = 0.00; ui_max = 1.00; ui_step = 0.01;
    ui_category = "Intox depth grader";
    ui_tooltip =
        "Linearized depth where the far grade starts to take over. Between\n"
        "the near band's end and this value the two stacks crossfade.";
> = 0.60;

uniform bool IntoxDCCPreviewMask <
    ui_label = "Show depth mask";
    ui_category = "Intox depth grader";
    ui_tooltip =
        "Replaces the picture with the blend mask: red is the near grade,\n"
        "blue the far grade. Turn it on while tuning band width and far\n"
        "start, then off again.";
> = false;

uniform float IntoxDCCNearExposure <
    ui_label = "Near exposure";
    ui_type = "slider";
    ui_min = -2.0; ui_max = 2.0; ui_step = 0.01;
    ui_category = "Intox near grade";
    ui_tooltip = "Exposure stops applied to the near band before every other control.";
> = 0.0;

uniform float IntoxDCCNearBrightness <
    ui_label = "Near brightness";
    ui_type = "slider";
    ui_min = -0.50; ui_max = 0.50; ui_step = 0.01;
    ui_category = "Intox near grade";
    ui_tooltip = "Adds after everything else; lifts or sinks the near band overall.";
> = 0.0;

uniform float IntoxDCCNearContrast <
    ui_label = "Near contrast";
    ui_type = "slider";
    ui_min = 0.50; ui_max = 1.50; ui_step = 0.01;
    ui_category = "Intox near grade";
    ui_tooltip = "Scales the near band around mid grey.";
> = 1.0;

uniform float IntoxDCCNearSaturation <
    ui_label = "Near saturation";
    ui_type = "slider";
    ui_min = 0.0; ui_max = 2.0; ui_step = 0.01;
    ui_category = "Intox near grade";
    ui_tooltip = "0 greys the near band, 1 keeps it, 2 doubles its colour.";
> = 1.0;

uniform float IntoxDCCNearTemperature <
    ui_label = "Near temperature";
    ui_type = "slider";
    ui_min = -1.0; ui_max = 1.0; ui_step = 0.01;
    ui_category = "Intox near grade";
    ui_tooltip = "Negative cools toward blue, positive warms toward amber.";
> = 0.0;

uniform float IntoxDCCNearTint <
    ui_label = "Near tint";
    ui_type = "slider";
    ui_min = -1.0; ui_max = 1.0; ui_step = 0.01;
    ui_category = "Intox near grade";
    ui_tooltip = "Negative leans green, positive leans magenta.";
> = 0.0;

uniform float IntoxDCCFarExposure <
    ui_label = "Far exposure";
    ui_type = "slider";
    ui_min = -2.0; ui_max = 2.0; ui_step = 0.01;
    ui_category = "Intox far grade";
    ui_tooltip = "Exposure stops applied to the far band before every other control.";
> = 0.0;

uniform float IntoxDCCFarBrightness <
    ui_label = "Far brightness";
    ui_type = "slider";
    ui_min = -0.50; ui_max = 0.50; ui_step = 0.01;
    ui_category = "Intox far grade";
    ui_tooltip = "Adds after everything else; lifts or sinks the far band overall.";
> = 0.0;

uniform float IntoxDCCFarContrast <
    ui_label = "Far contrast";
    ui_type = "slider";
    ui_min = 0.50; ui_max = 1.50; ui_step = 0.01;
    ui_category = "Intox far grade";
    ui_tooltip = "Scales the far band around mid grey.";
> = 1.0;

uniform float IntoxDCCFarSaturation <
    ui_label = "Far saturation";
    ui_type = "slider";
    ui_min = 0.0; ui_max = 2.0; ui_step = 0.01;
    ui_category = "Intox far grade";
    ui_tooltip = "0 greys the far band, 1 keeps it, 2 doubles its colour.";
> = 1.0;

uniform float IntoxDCCFarTemperature <
    ui_label = "Far temperature";
    ui_type = "slider";
    ui_min = -1.0; ui_max = 1.0; ui_step = 0.01;
    ui_category = "Intox far grade";
    ui_tooltip = "Negative cools toward blue, positive warms toward amber.";
> = 0.0;

uniform float IntoxDCCFarTint <
    ui_label = "Far tint";
    ui_type = "slider";
    ui_min = -1.0; ui_max = 1.0; ui_step = 0.01;
    ui_category = "Intox far grade";
    ui_tooltip = "Negative leans green, positive leans magenta.";
> = 0.0;

float3 IntoxDCCGrade(float3 color, float exposure, float brightness,
                     float contrast, float saturation, float temperature, float tint)
{
    color *= exp2(exposure);

    const float warm = saturate(temperature);
    const float cool = saturate(-temperature);
    color = lerp(color, color * float3(1.10, 1.02, 0.84), warm);
    color = lerp(color, color * float3(0.86, 0.98, 1.12), cool);

    const float green = saturate(-tint);
    const float magenta = saturate(tint);
    color = lerp(color, color * float3(0.95, 1.08, 0.95), green);
    color = lerp(color, color * float3(1.07, 0.95, 1.07), magenta);

    const float luma = dot(color, float3(0.2126, 0.7152, 0.0722));
    color = lerp(luma.xxx, color, saturation);

    color = (color - 0.5) * contrast + 0.5;
    color += brightness;

    return saturate(color);
}

float3 PS_IntoxDepthColorCorrection(float4 position : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    const float3 color = tex2D(ReShade::BackBuffer, texcoord).rgb;
    const float linNear = Intox::linear_depth(texcoord);

    if (IntoxDCCPreviewMask)
        return float3(1.0 - linNear, 0.0, linNear);

    if (linNear >= 1.0 || linNear >= 0.9999)
        return color;

    const float nearWeight = 1.0 - smoothstep(0.0, IntoxDCCTransition, linNear);
    const float farWeight = smoothstep(IntoxDCCFarStart, min(IntoxDCCFarStart + IntoxDCCTransition, 1.0), linNear);

    if (nearWeight <= 0.001 && farWeight <= 0.001)
        return color;

    float3 graded = color;

    if (nearWeight > 0.001)
    {
        const float3 nearGraded = IntoxDCCGrade(graded, IntoxDCCNearExposure, IntoxDCCNearBrightness,
                                                IntoxDCCNearContrast, IntoxDCCNearSaturation,
                                                IntoxDCCNearTemperature, IntoxDCCNearTint);
        graded = lerp(graded, nearGraded, nearWeight);
    }

    if (farWeight > 0.001)
    {
        const float farMix = farWeight * (1.0 - nearWeight);
        const float3 farGraded = IntoxDCCGrade(graded, IntoxDCCFarExposure, IntoxDCCFarBrightness,
                                               IntoxDCCFarContrast, IntoxDCCFarSaturation,
                                               IntoxDCCFarTemperature, IntoxDCCFarTint);
        graded = lerp(graded, farGraded, farMix);
    }

    return graded;
}

technique IntoxDepthColorCorrection <
    ui_label = "Intox depth colour grader";
    ui_tooltip =
        "Two grading stacks, near and far, crossfaded over depth. Grade what\n"
        "stands close to the player separately from the horizon: warmer and\n"
        "punchier up front, cooler and flatter far away. Use the depth mask\n"
        "preview to line the bands up before spending time on the colour\n"
        "controls.";
>
{
    pass
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_IntoxDepthColorCorrection;
    }
}
