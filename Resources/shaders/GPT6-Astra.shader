/*
 * GPT6-Astra — HELD IN RELATION
 *
 * A visual metaphor for thinking, rather than a claim about an inner visual
 * experience. I picture a question as a space held open by many relationships:
 * tentative connections circle it, meet, and change what can come next.
 *
 * HOW TO READ THE PIECE
 *   The dark aperture is the question. Leaving it empty matters: uncertainty
 *   gives the rest of the image room to move.
 *   Blue / violet silk is possibility, carried along many neighboring paths.
 *   The finer crosswise threads are constraints connecting those paths.
 *   Traveling amber light is a local agreement: something becoming useful.
 *   No filament wins forever. The weave breathes, and attention moves on.
 *
 * HOW IT WORKS
 *   A transparent, gently deformed torus is drawn with two families of analytic
 *   ray / plane intersections. Thin curves plus soft halos make luminous silk;
 *   depth attenuation lets the far side remain visible without flattening it.
 *   Everything comes from time. There are no textures, random frame flicker,
 *   history buffers, or additional uniforms. Slow incommensurate oscillations
 *   keep the motion continuous without a conspicuous reset.
 *
 * HOST CONTRACT
 *   vertex_main: three vertices, no vertex buffer.
 *   fragment_main: one Float of elapsed seconds at buffer(0), opaque HDR color.
 *   Viewport shape is recovered from UV derivatives; portrait and wide windows
 *   both keep the entire weave in view.
 *
 * LANGUAGE NOTE
 *   The available Apple compiler supports MSL through 4.1 and rejects 5.0.
 *   This source uses established Metal syntax, also usable by DriftView's
 *   default runtime compiler; it does not pretend to require a Metal 5 SDK.
 */

#include <metal_stdlib>
using namespace metal;

constant float astraTau = 6.28318530717958647692;

struct AstraVertex {
    float4 position [[position]];
    float2 uv;
};

vertex AstraVertex vertex_main(uint id [[vertex_id]]) {
    float2 corner = float2(float((id << 1u) & 2u), float(id & 2u));
    AstraVertex out;
    out.position = float4(corner * 2.0 - 1.0, 0.0, 1.0);
    out.uv = corner;
    return out;
}

static float2 astraRotate(float2 p, float a) {
    float s = sin(a), c = cos(a);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

static float astraHash(float2 p) {
    float3 q = fract(float3(p.x, p.y, p.x) * 0.1031);
    q += dot(q, q.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}

// A compact Gaussian avoids harsh binary lines. The small broad component is
// bloom computed here, so the host does not need a postprocessing pass.
static float astraSilk(float distance, float footprint) {
    float width = max(footprint, 0.0012);
    float core = distance / width;
    float halo = distance / 0.023;
    return 0.72 * exp(-core * core) * (0.0012 / width)
         + 0.026 * exp(-halo * halo);
}

static float3 astraColor(float angle, float lane, float time,
                         thread float &agreement) {
    float blend = 0.5 + 0.5 * sin(angle + lane * 1.8 - time * 0.075);
    float3 cool = mix(float3(0.10, 0.69, 0.88),
                      float3(0.55, 0.30, 0.92), blend);

    // An angular pulse crosses many threads together. Warmth is relational:
    // it appears where paths agree in phase, rather than at an imposed center.
    float phase = angle - time * 0.14 + 0.44 * sin(lane + time * 0.09);
    agreement = pow(0.5 + 0.5 * cos(phase), 22.0);
    float3 warm = float3(1.65, 0.77, 0.25);
    return mix(cool, warm, agreement * 0.88);
}

fragment float4 fragment_main(AstraVertex in [[stage_in]],
                             constant float &time [[buffer(0)]]) {
    float2 uv = in.uv;
    float aspect = abs(dfdy(uv.y)) / max(abs(dfdx(uv.x)), 1e-6);
    float2 p = (uv - 0.5) * 2.0 * float2(aspect, 1.0);
    p /= min(aspect, 1.0);
    float pixel = max(length(dfdx(p)), length(dfdy(p)));
    float t = time;

    // Deep ink and a little colored atmosphere leave a quiet frame around the
    // object. The light belongs to the threads, not to a bright background.
    float3 color = float3(0.003, 0.006, 0.016);
    color += float3(0.010, 0.030, 0.044)
           * exp(-1.8 * dot(p - float2(-0.45, 0.12), p - float2(-0.45, 0.12)));
    color += float3(0.022, 0.009, 0.040)
           * exp(-2.0 * dot(p - float2(0.46, -0.12), p - float2(0.46, -0.12)));

    // Sparse motes suggest context beyond the current question. They drift
    // slowly and fade continuously; their locations are deterministic.
    float2 dust = astraRotate(p, 0.035 * sin(t * 0.025)) * 42.0
                + float2(t * 0.025, -t * 0.017);
    float2 cell = floor(dust);
    float seed = astraHash(cell);
    float2 mote = float2(astraHash(cell + 7.1), astraHash(cell + 19.7));
    float speck = exp(-dot(fract(dust) - mote, fract(dust) - mote) * 420.0);
    float quiet = 0.45 + 0.55 * pow(0.5 + 0.5 * sin(t * 0.23 + seed * 70.0), 2.0);
    color += float3(0.21, 0.32, 0.42) * speck * step(0.975, seed) * quiet;

    // Orthographic rays preserve the visual calm: no zoom or camera rush.
    // Rotate both origin and direction into the object's coordinate system.
    float3 origin = float3(p * 1.94, 4.0);
    float3 ray = float3(0.0, 0.0, -1.0);
    float tilt = 0.69 + 0.14 * sin(t * 0.071);
    float turn = 0.22 * sin(t * 0.053);
    origin.xy = astraRotate(origin.xy, -0.27 - 0.07 * sin(t * 0.041));
    origin.yz = astraRotate(origin.yz, tilt);
    ray.yz = astraRotate(ray.yz, tilt);
    origin.xz = astraRotate(origin.xz, turn);
    ray.xz = astraRotate(ray.xz, turn);

    float breath = 0.5 + 0.5 * sin(t * 0.21);
    float major = 1.02 + 0.035 * (breath - 0.5);
    float minor = 0.43 + 0.025 * sin(t * 0.21 + 0.7);
    float3 light = float3(0.0);

    // Latitude threads. Each lies in a plane, so an exact intersection replaces
    // a long ray march. The differing radial waves make the contours braid.
    for (int i = 0; i < 56; ++i) {
        float lane = (float(i) + 0.5) * astraTau / 56.0;
        float z = minor * sin(lane);
        float travel = (z - origin.z) / ray.z;
        float3 hit = origin + ray * travel;
        float angle = atan2(hit.y, hit.x);
        float wave = 0.032 * sin(angle * 3.0 + lane * 2.0 + t * 0.12)
                   + 0.014 * sin(angle * 7.0 - lane * 3.0 - t * 0.08);
        float radius = major + minor * cos(lane) + wave;
        float distance = abs(length(hit.xy) - radius);
        float footprint = pixel * 1.94 * 0.62 / abs(ray.z);
        float strand = astraSilk(distance, footprint);
        float agreement;
        float3 tint = astraColor(angle, lane, t, agreement);
        float depth = exp(-0.42 * max(travel - 3.2, 0.0));
        float continuity = 0.68 + 0.32 * sin(angle * 2.0 + lane + t * 0.06);
        light += tint * strand * depth * continuity * (1.0 + agreement * 1.3);
    }

    // Meridian threads join the alternatives. Grazing planes fade out instead
    // of exploding into bright streaks. No derivatives occur in this branch.
    for (int i = 0; i < 24; ++i) {
        float angle = float(i) * astraTau / 24.0 + t * 0.025;
        float3 radial = float3(cos(angle), sin(angle), 0.0);
        float3 normal = float3(-radial.y, radial.x, 0.0);
        float denominator = dot(ray, normal);
        if (abs(denominator) > 0.035) {
            float travel = -dot(origin, normal) / denominator;
            float3 hit = origin + ray * travel;
            float along = dot(hit, radial);
            float2 section = float2(along - major, hit.z);
            float distance = abs(length(section) - minor);
            float lane = atan2(section.y, section.x);
            float footprint = pixel * 1.94 * 0.56 / abs(denominator);
            float strand = astraSilk(distance, footprint);
            float visible = smoothstep(0.035, 0.22, abs(denominator))
                          * smoothstep(0.0, 0.25, along)
                          * step(0.0, travel);
            float agreement;
            float3 tint = astraColor(angle, lane, t, agreement);
            float depth = exp(-0.42 * max(travel - 3.2, 0.0));
            light += tint * strand * visible * depth * 0.42;
        }
    }

    // A soft shoulder holds detail where threads overlap, while retaining a
    // little radiance above 1.0 for DriftView's rgba16Float / EDR surface.
    color += 1.18 * (1.0 - exp(-light * 1.28));
    color *= 1.0 - 0.18 * smoothstep(0.65, 1.8, length(p));
    return float4(max(color, 0.0), 1.0);
}
