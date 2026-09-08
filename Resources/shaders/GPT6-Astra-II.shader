/*
 * GPT6-Astra II — ALMOST A SHAPE
 *
 * A second visual metaphor for reasoning.
 *
 * Two neighboring systems of contours keep revising their relationship.
 * Sometimes each can be read alone. Sometimes a shared outline encloses both.
 * The change happens at the saddle between them: a small local difference
 * changes the interpretation of the whole picture.
 *
 * WHY THESE CHOICES
 *   Ivory is space to revise. Graphite contours are the nearby interpretations
 *   that remain available. Vermilion follows one provisional reading.
 *   That red line is allowed to split. A useful answer need not make everything
 *   belong to one shape, and clarity need not be permanent.
 *   Off-center asymmetry and paper grain keep the geometry from becoming an
 *   emblem. There is no final pose, winning flash, or regularly resetting loop.
 *
 * HOW
 *   Three smooth fields overlap in a slowly deformed coordinate system. Their
 *   level sets form a contour drawing. A highlighted level passes through the
 *   changing saddle, naturally merging and separating without crossfades.
 *   Screen derivatives give both antialiasing and shallow relief. The grain is
 *   fixed to the paper, so it does not sparkle as the contours move.
 *
 * DriftView contract: fullscreen triangle; Float time at fragment buffer(0);
 * opaque linear color for rgba16Float. No textures or additional uniforms.
 * Uses supported Metal shading-language syntax (validated with MSL 4.1).
 */

#include <metal_stdlib>
using namespace metal;

struct AstraIIVertex {
    float4 position [[position]];
    float2 uv;
};

vertex AstraIIVertex vertex_main(uint id [[vertex_id]]) {
    float2 uv = float2(float((id << 1u) & 2u), float(id & 2u));
    return { float4(uv * 2.0 - 1.0, 0.0, 1.0), uv };
}

static float2 a2Rotate(float2 p, float angle) {
    float s = sin(angle), c = cos(angle);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

static float a2Hash(float2 p) {
    float3 q = fract(float3(p.x, p.y, p.x) * 0.1031);
    q += dot(q, q.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}

static float a2Noise(float2 p) {
    float2 cell = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(a2Hash(cell), a2Hash(cell + float2(1, 0)), f.x),
               mix(a2Hash(cell + float2(0, 1)), a2Hash(cell + 1.0), f.x), f.y);
}

// The small third contribution is context: it nudges the relationship between
// the two main shapes without becoming a separate central object.
static float a2Field(float2 p, float t) {
    float2 q = a2Rotate(p, 0.30 + 0.16 * sin(t * 0.037));
    q += 0.09 * float2(sin(2.8 * q.y + t * 0.057),
                       sin(3.2 * q.x - t * 0.043));
    q += 0.022 * float2(sin(7.0 * q.y + q.x + t * 0.081),
                        cos(6.0 * q.x - q.y - t * 0.062));

    float separation = 0.49 + 0.13 * sin(t * 0.095 - 0.6);
    float2 a = q - float2(-separation, 0.08 * sin(t * 0.052));
    float2 b = q - float2(separation, -0.06 + 0.09 * cos(t * 0.047));
    a = a2Rotate(a, -0.22);
    b = a2Rotate(b, 0.36 + 0.13 * sin(t * 0.061));
    a *= float2(0.95, 1.20);
    b *= float2(1.06, 0.94);
    float2 c = q - float2(0.02 + 0.12 * sin(t * 0.031), 0.37);
    return exp(-4.8 * dot(a, a))
         + (0.94 + 0.05 * sin(t * 0.073)) * exp(-4.8 * dot(b, b))
         + 0.23 * exp(-7.0 * dot(c, c));
}

// The energy correction keeps tightly packed lines from filling a whole pixel
// with ink at small sizes. Derivatives are evaluated before any selection.
static float a2Contour(float phase, float footprint, float width) {
    float distance = abs(fract(phase + 0.5) - 0.5);
    float aa = max(footprint, 0.001);
    float coverage = 1.0 - smoothstep(width, width + aa, distance);
    return coverage * min(1.0, 0.30 / aa);
}

fragment float4 fragment_main(AstraIIVertex in [[stage_in]],
                             constant float &time [[buffer(0)]]) {
    float2 uv = in.uv;
    float aspect = abs(dfdy(uv.y)) / max(abs(dfdx(uv.x)), 1e-6);
    float2 p = (uv - 0.5) * 2.0 * float2(aspect, 1.0) / min(aspect, 1.0);
    p *= 1.95;
    float pixel = max(length(dfdx(p)), length(dfdy(p)));
    float t = time;

    float grain = a2Hash(floor(in.position.xy)) - 0.5;
    float fiber = a2Noise(p * float2(85.0, 260.0)) - 0.5;
    float3 paper = float3(0.87, 0.835, 0.745);
    paper += (grain * 0.012 + fiber * 0.009);
    paper -= 0.022 * smoothstep(0.4, 2.5, length(p));
    float3 color = paper;

    float field = a2Field(p, t);
    // Square root distributes the levels across the outskirts as well as the
    // summits. The outer contours disappear softly into unmarked paper.
    float height = sqrt(max(field, 0.0));
    float dx = dfdx(height), dy = dfdy(height);
    float footprint = max(abs(dx) + abs(dy), 1e-5);
    float presence = smoothstep(0.11, 0.24, height);
    float rim = smoothstep(0.16, 0.28, height);

    // A shallow paper relief: light reaches the upper-left side of each fold.
    // This shading depends on the changing surface, not a painted drop shadow.
    float directional = (dx * 0.58 - dy * 0.81) / max(pixel, 1e-5);
    float relief = tanh(directional * 0.72);
    color -= float3(0.085, 0.075, 0.055) * presence;
    color += float3(0.066, 0.061, 0.046) * relief * presence;

    float phase = height * 54.0;
    float ink = a2Contour(phase, footprint * 54.0, 0.017);
    float major = a2Contour(phase / 6.0, footprint * 9.0, 0.012);
    float3 graphite = float3(0.080, 0.095, 0.089);
    color = mix(color, graphite, presence * (ink * 0.64 + major * 0.20));

    // A nearby pale impression offsets the dark lines by a fraction of a
    // contour interval, giving them the quality of embossed, translucent paper.
    float impression = a2Contour(phase + 0.20, footprint * 54.0, 0.012);
    color = mix(color, paper + 0.05, impression * rim * 0.30);

    // One chosen reading. Its topology changes when this value crosses the
    // field's saddle. Keep the line visible across the whole scene: attention
    // can describe a relationship without sitting at a single bright point.
    float chosen = 0.835 + 0.025 * sin(t * 0.067 + 0.8);
    float delta = abs(height - chosen);
    float redLine = 1.0 - smoothstep(footprint * 0.48, footprint * 1.8, delta);
    float bleed = exp(-delta * delta / 0.00010);
    float3 vermilion = float3(0.62, 0.064, 0.028);
    color = mix(color, float3(0.69, 0.24, 0.105), bleed * 0.12);
    color = mix(color, vermilion, redLine * 0.91);

    // Broad, almost imperceptible variation belongs to the support, not the
    // contour system. There is room to look away from the proposed answer.
    color *= 0.985 + 0.015 * a2Noise(p * 2.0 + 17.0);
    return float4(max(color, 0.0), 1.0);
}
