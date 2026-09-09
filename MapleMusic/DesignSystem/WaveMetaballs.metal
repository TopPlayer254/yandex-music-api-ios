#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

static float2 mapleAspectPoint(float2 normalizedPoint, float aspectRatio) {
    return float2((normalizedPoint.x - 0.5) * aspectRatio, normalizedPoint.y - 0.5);
}

static float mapleMetaball(float2 point, float2 center, float radius) {
    float squaredDistance = max(dot(point - center, point - center), 0.001);
    return (radius * radius) / squaredDistance;
}

[[ stitchable ]] half4 mapleWaveMetaballs(
    float2 position,
    half4 sourceColor,
    float2 size,
    float time,
    half4 primaryColor,
    half4 secondaryColor,
    half4 tertiaryColor
) {
    float2 safeSize = max(size, float2(1.0));
    float aspectRatio = safeSize.x / safeSize.y;
    float2 point = mapleAspectPoint(position / safeSize, aspectRatio);

    float2 firstCenter = mapleAspectPoint(float2(
        0.18 + 0.11 * sin(time * 0.62),
        0.30 + 0.16 * cos(time * 0.47)
    ), aspectRatio);
    float2 secondCenter = mapleAspectPoint(float2(
        0.52 + 0.16 * cos(time * 0.39 + 1.4),
        0.64 + 0.14 * sin(time * 0.56)
    ), aspectRatio);
    float2 thirdCenter = mapleAspectPoint(float2(
        0.82 + 0.10 * sin(time * 0.51 + 2.2),
        0.32 + 0.18 * cos(time * 0.43 + 0.8)
    ), aspectRatio);

    float firstWeight = mapleMetaball(point, firstCenter, 0.27);
    float secondWeight = mapleMetaball(point, secondCenter, 0.31);
    float thirdWeight = mapleMetaball(point, thirdCenter, 0.25);
    float totalWeight = firstWeight + secondWeight + thirdWeight;

    float3 mixedColor = (
        float3(primaryColor.rgb) * firstWeight
        + float3(secondaryColor.rgb) * secondWeight
        + float3(tertiaryColor.rgb) * thirdWeight
    ) / max(totalWeight, 0.001);
    float body = smoothstep(0.68, 1.38, totalWeight);
    float rim = smoothstep(0.62, 0.88, totalWeight) - smoothstep(1.05, 1.48, totalWeight);
    float shimmer = 0.5 + 0.5 * sin((point.x - point.y) * 8.0 + time * 0.72);
    float3 backgroundColor = mix(float3(0.025, 0.028, 0.040), mixedColor * 0.42, 0.54);
    float3 finalColor = mix(backgroundColor, mixedColor, body * 0.82);
    finalColor += rim * (0.08 + shimmer * 0.08);

    return half4(half3(finalColor), half(0.96));
}
