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

static float3 mapleWaveWeights(float2 point, float aspectRatio, float time) {
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
    return float3(
        mapleMetaball(point, firstCenter, 0.27),
        mapleMetaball(point, secondCenter, 0.31),
        mapleMetaball(point, thirdCenter, 0.25)
    );
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

    float3 weights = mapleWaveWeights(point, aspectRatio, time);
    float firstWeight = weights.x;
    float secondWeight = weights.y;
    float thirdWeight = weights.z;
    float totalWeight = firstWeight + secondWeight + thirdWeight;

    float3 mixedColor = (
        float3(primaryColor.rgb) * firstWeight
        + float3(secondaryColor.rgb) * secondWeight
        + float3(tertiaryColor.rgb) * thirdWeight
    ) / max(totalWeight, 0.001);
    float body = smoothstep(0.68, 1.38, totalWeight);
    float rim = smoothstep(0.62, 0.88, totalWeight) - smoothstep(1.05, 1.48, totalWeight);
    float shimmer = 0.5 + 0.5 * sin((point.x - point.y) * 8.0 + time * 0.72);
    float3 finalColor = mix(mixedColor * 0.34, mixedColor, body * 0.82);
    finalColor += rim * (0.08 + shimmer * 0.08);
    float alpha = smoothstep(0.42, 0.90, totalWeight) * 0.92;

    return half4(half3(finalColor * alpha), half(alpha));
}

[[ stitchable ]] half4 mapleWaveGlass(
    float2 position,
    SwiftUI::Layer layer,
    float2 size,
    float time,
    half4 primaryColor,
    half4 secondaryColor,
    half4 tertiaryColor
) {
    float2 safeSize = max(size, float2(1.0));
    float aspectRatio = safeSize.x / safeSize.y;
    float2 point = mapleAspectPoint(position / safeSize, aspectRatio);
    float3 weights = mapleWaveWeights(point, aspectRatio, time);
    float totalWeight = weights.x + weights.y + weights.z;
    float mask = smoothstep(0.58, 1.02, totalWeight);

    float epsilon = 0.004;
    float horizontal = dot(
        mapleWaveWeights(point + float2(epsilon, 0), aspectRatio, time)
            - mapleWaveWeights(point - float2(epsilon, 0), aspectRatio, time),
        float3(1.0)
    );
    float vertical = dot(
        mapleWaveWeights(point + float2(0, epsilon), aspectRatio, time)
            - mapleWaveWeights(point - float2(0, epsilon), aspectRatio, time),
        float3(1.0)
    );
    float2 gradient = normalize(float2(horizontal, vertical) + float2(0.0001));
    float rim = smoothstep(0.58, 0.84, totalWeight) - smoothstep(1.00, 1.34, totalWeight);
    half4 sampled = layer.sample(position + gradient * (10.0 + 12.0 * rim));

    float3 mixedColor = (
        float3(primaryColor.rgb) * weights.x
        + float3(secondaryColor.rgb) * weights.y
        + float3(tertiaryColor.rgb) * weights.z
    ) / max(totalWeight, 0.001);
    float shimmer = 0.5 + 0.5 * sin((point.x - point.y) * 9.0 + time * 0.8);
    float3 glassColor = mix(float3(sampled.rgb), mixedColor, 0.16);
    glassColor += rim * (0.18 + 0.12 * shimmer);
    float alpha = mask * 0.94;
    return half4(half3(glassColor * alpha), half(alpha));
}
