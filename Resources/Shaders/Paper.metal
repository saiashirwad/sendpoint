#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// A cheap, stable hash: the grain must not shimmer between frames.
static float hash21(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

/// The sheet every Sendpoint surface is drawn on: the flat surface colour,
/// a soft warm light near the top-left that wanders very slowly, a faint
/// top-to-bottom falloff for depth, and a fine grain so the surface has
/// tooth instead of reading as a flat fill.
[[ stitchable ]] half4 paper(
    float2 position, half4 color,
    float2 size, float time, half4 tint,
    float glow, float depth, float grain
) {
    float2 uv = position / max(size, float2(1.0));
    float aspect = size.y / max(size.x, 1.0);

    float2 center = float2(0.16 + 0.10 * sin(time * 0.11), 0.02 + 0.08 * cos(time * 0.09));
    float2 d = (uv - center) * float2(1.0, aspect);
    float light = exp(-dot(d, d) * 7.0);

    half3 sheet = mix(color.rgb, tint.rgb, half(glow * light));
    sheet += half3(depth * (0.5 - uv.y));
    sheet += half3((hash21(position) - 0.5) * grain);
    return half4(sheet, color.a);
}

/// Three soft pools of colour drifting over the paper, fading out towards
/// the bottom: the status card's living background.
[[ stitchable ]] half4 aurora(
    float2 position, half4 color,
    float2 size, float time, half4 a, half4 b, half4 c, float strength
) {
    float2 uv = position / max(size, float2(1.0));
    float aspect = size.y / max(size.x, 1.0);
    float2 p = uv * float2(1.0, aspect);

    float2 ca = float2(0.22 + 0.10 * sin(time * 0.21), 0.08 * aspect + 0.06 * cos(time * 0.17));
    float2 cb = float2(0.78 + 0.10 * cos(time * 0.15), 0.12 * aspect + 0.06 * sin(time * 0.19));
    float2 cc = float2(0.50 + 0.14 * sin(time * 0.12), 0.45 * aspect + 0.05 * cos(time * 0.14));

    float wa = exp(-dot(p - ca, p - ca) * 9.0);
    float wb = exp(-dot(p - cb, p - cb) * 9.0);
    float wc = exp(-dot(p - cc, p - cc) * 11.0);
    float fade = smoothstep(1.0, 0.25, uv.y);

    half3 sheet = color.rgb;
    sheet = mix(sheet, a.rgb, half(strength * wa * fade));
    sheet = mix(sheet, b.rgb, half(strength * wb * fade));
    sheet = mix(sheet, c.rgb, half(strength * 0.7 * wc * fade));
    return half4(sheet, color.a);
}
