#include <metal_stdlib>
using namespace metal;

// WEATHER — a miniature weather system.
// A wide, empty sky above a drowned valley. The hills are permanent; only
// the air changes. No sun disc, horizon flare, or literal weather information.
// A paused frame is a complete landscape, rather than a simulation mid-step.
//
// Host contract: fullscreen triangle, Float shader time at fragment buffer 0.
// Aspect is recovered from UV derivatives, so no resolution uniform is needed.
// Colors are authored in sRGB and converted to linear at the end, matching the
// native renderer's rgba16Float -> bgra8Unorm_srgb display conversion.

struct WeatherVertex {
    float4 position [[position]];
    float2 uv;
};

vertex WeatherVertex vertex_main(uint index [[vertex_id]]) {
    float2 uv = float2(float((index << 1u) & 2u), float(index & 2u));
    return { float4(uv * 2.0 - 1.0, 0.0, 1.0), uv };
}

float weatherHash(float2 p) {
    float3 q = fract(float3(p.xyx) * float3(0.1031, 0.1030, 0.0973));
    q += dot(q, q.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}

float weatherNoise(float2 p) {
    float2 cell = floor(p), f = fract(p);
    f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    return mix(mix(weatherHash(cell), weatherHash(cell + float2(1, 0)), f.x),
               mix(weatherHash(cell + float2(0, 1)), weatherHash(cell + 1.0), f.x), f.y);
}

float weatherFbm(float2 p) {
    // Incommensurate rotations prevent recognizable stacks of repeated noise.
    float s = 0.0, a = 0.56;
    for (int i = 0; i < 4; ++i) {
        s += a * weatherNoise(p);
        p = float2(1.71*p.x - 1.13*p.y, 1.13*p.x + 1.71*p.y) + float2(9.2, 3.7);
        a *= 0.46;
    }
    return s;
}

float weatherHill(float x, float center, float width) {
    float d = (x - center) / width;
    return exp(-d*d);
}

float weatherRidge(float x, float depth) {
    // Deliberate overlapping shoulders establish a valley; noise only gives
    // the silhouettes an eroded edge. Depth 0 is the farthest landform.
    const float bases[6] = {0.325, 0.285, 0.175, 0.080, -0.025, -0.130};
    const float leftPeaks[6] = {0.095, 0.050, 0.165, 0.160, 0.255, 0.340};
    const float rightPeaks[6] = {0.060, 0.105, 0.130, 0.220, 0.240, 0.340};
    const float leftCenters[6] = {-0.52, -0.94, -0.59, -0.92, -0.94, -0.96};
    const float rightCenters[6] = {0.80, 0.50, 0.89, 0.66, 0.90, 0.77};
    int index = int(depth);
    float seed = depth * 13.71;
    float base = bases[index];
    float shoulders = leftPeaks[index] * weatherHill(x, leftCenters[index], 0.43 + depth*0.019)
                    + rightPeaks[index] * weatherHill(x, rightCenters[index], 0.47 + depth*0.013);
    float center = (index == 2 ? 0.091 : 0.034) * weatherHill(x, index == 2 ? -0.08 : 0.12, 0.23);
    float worn = weatherFbm(float2(x*(3.4 + depth*0.43) + seed, 5.3 + seed));
    return base + shoulders + center + (worn - 0.48) * (0.046 + depth*0.005);
}

float3 weatherLinear(float3 c) {
    return select(c / 12.92, pow((c + 0.055) / 1.055, float3(2.4)), c > 0.04045);
}

fragment float4 fragment_main(WeatherVertex in [[stage_in]], constant float &time [[buffer(0)]]) {
    float2 uv = in.uv; // bottom-left origin, matching the fullscreen triangle.
    float aspect = abs(dfdy(uv.y)) / max(abs(dfdx(uv.x)), 1.0e-7);
    // Narrow displays reframe the whole basin instead of cropping down to
    // its empty center. Wide displays reveal the outer slopes naturally.
    float landscapeWidth = max(aspect, 1.60);
    float2 p = float2((uv.x - 0.5) * landscapeWidth, uv.y);
    float pixel = max(abs(dfdy(uv.y)), 1.0e-5);
    // All changes are continuous in time, no resets or animation loops.
    // Very low rates tolerate Float time precision over lengthy saved sessions.
    float t = time;
    float light = 0.5 + 0.5*sin(t*0.0023 + 0.6);
    float warmth = 0.5 + 0.5*sin(t*0.0017 - 0.4);
    float3 upperSky = mix(float3(0.51,0.585,0.605), float3(0.555,0.620,0.630), light);
    float3 lowerSky = mix(float3(0.805,0.802,0.746), float3(0.846,0.804,0.707), warmth);
    float horizonGlow = exp(-pow((uv.y-0.37)/0.35, 2.0));
    float3 color = mix(upperSky, lowerSky, horizonGlow);
    float opening = exp(-pow((p.x+0.40+0.12*sin(t*0.0011))/0.80, 2.0));
    color += float3(0.021, 0.017, 0.007) * opening * horizonGlow;

    // Cloudless at first glance: broad, faint weather veils live in the sky.
    // No small-scale animated detail, so the desktop never looks like static.
    float skyVeil = weatherFbm(float2(p.x*1.35-t*0.0007, p.y*3.4+4.8));
    color += (skyVeil-0.48) * 0.024 * smoothstep(0.30, 0.80, uv.y);

    float3 air = mix(float3(0.72,0.752,0.724), float3(0.779,0.773,0.711), warmth*0.60);
    // Every ridge is below 0.70 even under the conservative sum-of-peaks
    // bound. Skip their noise entirely in the upper sky, including tiny views.
    if (p.y < 0.70 + pixel) {
    for (int i = 0; i < 6; ++i) {
        float d = float(i);
        float height = weatherRidge(p.x, d);
        float below = height-p.y;
        float edge = 0.00075 + (5.0-d)*0.00048;
        float mask = smoothstep(-edge-pixel, edge+pixel, below);
        if (mask > 0.0) {
            float distance = d/5.0;
            float3 stone = mix(float3(0.554,0.624,0.615), float3(0.191,0.285,0.295), pow(distance,0.82));
            // A fixed, low-contrast relief field runs down the slopes. It is
            // not advected with the mist, so mountains retain their mass.
            float relief = weatherFbm(float2(p.x*(7.0+d*0.6)+d*8.1+below*2.1, p.y*4.0+d*4.2));
            float folds = weatherNoise(float2(p.x*(24.0+d*3.0)+relief*5.0, below*10.0+d*15.8));
            float patina = weatherFbm(float2(p.x*13.0+relief*2.0+d*12.0, below*18.0+d*4.3));
            float3 land = stone + (relief-0.48)*float3(0.130,0.142,0.119)*(0.35+distance)
                                + (folds-0.5)*0.027*distance
                                + (patina-0.48)*float3(0.045,0.049,0.047)*distance;
            land += float3(0.026,0.023,0.011)*opening*(0.6+0.4*light);
            // Each valley holds its own slow, irregular bank of low vapor.
            // Two domain-warped scales and different drift rates avoid moving
            // a single conspicuous flat noise sheet across the whole picture.
            float2 flow = float2(p.x*2.6-t*(0.0010+d*0.000085)+d*5.73,
                                 p.y*8.0+d*3.1);
            float warp = weatherNoise(flow*0.63+float2(0.0,t*0.00027));
            float vapor = weatherFbm(flow+float2(warp*1.25,warp*0.66));
            float fogLine = 0.295-d*0.032 + (vapor-0.46)*0.092;
            float fog = exp(-max(0.0,p.y-fogLine)*max(0.0,p.y-fogLine)/0.0019);
            fog *= 0.75 - d*0.046;
            fog *= 0.79+0.21*weatherNoise(float2(p.x*4.0+d*2.7-t*0.0015, p.y*13.0));
            float3 mist = mix(air, float3(0.605,0.672,0.648), distance*0.42);
            land = mix(land, mist, fog);
            color = mix(color, land, mask);
        }
    }
    }

    // Feather-light near-ground wisps unify the foreground without veiling
    // all contours. The bottom corners remain an anchor for the composition.
    float basin = exp(-pow((p.x+0.04)/0.47,2.0));
    float closeMist = weatherFbm(float2(p.x*4.3-t*0.0019, p.y*12.0+17.0));
    float closeMask = exp(-pow((p.y-0.105-(closeMist-0.48)*0.085)/0.10,2.0));
    color = mix(color, air*0.98, basin*closeMask*0.24);

    // A stable sub-visible grain breaks 8-bit gradients without crawling when
    // time is eased to a stop. Output stays comfortably inside the SDR range.
    float grain = weatherHash(in.position.xy) - 0.5;
    color += grain / 600.0;
    return float4(weatherLinear(clamp(color,0.0,1.0)), 1.0);
}
