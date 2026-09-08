#include <metal_stdlib>
using namespace metal;

/*
 LIGHT THROUGH GLASS
 A turning, unseen piece of imperfect glass gathers afternoon light on plaster.
 The glass itself is outside the image: only its defocused shadow, transmitted
 illumination and folded caustic are visible. The broad empty left field is
 deliberate room for desktop icons, and the form stays inside portrait crops.

 This is an analytic optical study, not a photon simulation. A deformed polar
 fold stands in for the envelope of refracted rays. Its narrow focus and broad,
 one-sided skirt suggest finite light-source size; a second fold describes a
 thicker part of the glass. Dispersion is confined to a small section of the
 focus. Everything is a function of position and the host's saved shader time:
 no feedback, textures, new uniforms, or dependence on the previous frame.
 Slow, bounded motions never rebuild the composition or flash on a clock wrap.
*/

struct LightVertex {
    float4 position [[position]];
    float2 uv;
};

vertex LightVertex vertex_main(uint id [[vertex_id]]) {
    float2 uv = float2(float((id << 1u) & 2u), float(id & 2u));
    return {float4(uv * 2.0 - 1.0, 0.0, 1.0), uv};
}

static float2 lightRotate(float2 p, float a) {
    float s = sin(a), c = cos(a);
    return float2(c*p.x-s*p.y, s*p.x+c*p.y);
}

static float lightGrain(float2 p) {
    // Static screen-space plaster grain; it does not boil as the light moves.
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x+p3.y)*p3.z);
}

static float lightStone(float2 p) {
    float2 cell = floor(p), f = fract(p);
    f = f*f*(3.0-2.0*f);
    return mix(mix(lightGrain(cell),lightGrain(cell+float2(1,0)),f.x),
               mix(lightGrain(cell+float2(0,1)),lightGrain(cell+float2(1,1)),f.x),f.y);
}

static float lightGaussian(float x, float w) {
    float q = x/w;
    return exp(-q*q);
}

static float lightFold(float d, float w) {
    // A soft shoulder on the transmitted side prevents a drawn-outline look.
    return lightGaussian(d,w) + 0.24*lightGaussian(d-2.0*w,3.8*w);
}

fragment float4 fragment_main(LightVertex in [[stage_in]],
                             constant float &time [[buffer(0)]]) {
    // Fragment derivatives recover shape-correct coordinates without adding
    // resolution uniforms to the renderer's established interface.
    float aspect = abs(dfdy(in.uv.y))/max(abs(dfdx(in.uv.x)),1e-7);
    float small = min(aspect,1.0);
    float2 p = (in.uv-0.5)*float2(aspect,1.0)/small;
    float pixel = abs(dfdy(in.uv.y))/small;
    float t = time;
    float turn = 0.11*sin(t*0.021) + 0.04*sin(t*0.013+1.7);
    float breathe = sin(t*0.026+0.5);
    float sway = sin(t*0.017+2.2);
    float2 center = float2(0.025+0.19*smoothstep(1.0,1.65,aspect),-0.045);
    center += float2(0.018*sin(t*0.015),0.012*sway);
    float2 world = p-center;
    float2 q = lightRotate(world,-0.40-turn);
    float2 axes = float2(0.420+0.009*breathe,0.215+0.007*sway);
    float2 z = q/axes;
    float theta = atan2(z.y,z.x);
    float radius = length(z);
    float c = cos(theta), s = sin(theta);
    float radiusAtAngle = 0.86 + 0.26*c - 0.23*cos(2.0*theta+0.35+turn)
                         + 0.060*sin(3.0*theta-0.7+turn);
    float dr = -0.26*s + 0.46*sin(2.0*theta+0.35+turn)
               + 0.180*cos(3.0*theta-0.7+turn);
    // Evaluate the metric at the contour, not at the query point: using the
    // query radius would generate a false concentrated fold near the origin.
    float2 grad = float2(c+dr*s/max(radiusAtAngle,0.1),s-dr*c/max(radiusAtAngle,0.1))/axes;
    float distance = (radius-radiusAtAngle)/max(length(grad),0.2);
    float aa = max(pixel*0.7,0.0003);

    // Warm, matte ground. The large oblique wash is incoming daylight, whose
    // shape is independent of the glass so the ground continues off-screen.
    float wash = exp(-dot((p-float2(0.30,-0.18))/float2(0.92,0.78),
                         (p-float2(0.30,-0.18))/float2(0.92,0.78)));
    float3 color = float3(0.310,0.277,0.233);
    color += float3(0.140,0.133,0.115)*wash;
    color += 0.025*(in.uv.y-0.5)*float3(1.0,0.94,0.82);
    float grain = lightGrain(in.position.xy)-0.5;
    float stone = (lightStone(p*5.0+11.0)-0.5)*0.006
                +(lightStone(p*37.0+3.0)-0.5)*0.003;
    color += grain*0.0022+stone;

    // A displaced, thoroughly defocused shadow gives the illumination weight
    // without suggesting an outlined glass object sitting on the desktop.
    float2 shadowQ = lightRotate(world-float2(-0.026,0.050),-0.40-turn)/axes;
    float shadowR = length(shadowQ);
    float shadowA = atan2(shadowQ.y,shadowQ.x);
    float shadowEdge = shadowR-(0.86+0.26*cos(shadowA)-0.23*cos(2.0*shadowA+0.35+turn));
    float shadow = lightGaussian(shadowEdge,0.32)*(0.5+0.5*sin(shadowA+0.8));
    color *= 1.0-0.27*shadow;

    // Light pooled inside the fold is broad and almost colorless. The small
    // asymmetry lets it read as an optical footprint rather than a perfect rim.
    float pool = exp(-dot((z-float2(0.22,-0.24))*float2(0.94,1.43),
                         (z-float2(0.22,-0.24))*float2(0.94,1.43))*1.7);
    color += float3(0.155,0.141,0.105)*pool;
    float arc = pow(clamp(0.5-0.5*sin(theta+0.36),0.0,1.0),1.4);
    float notch = 0.10+0.90*smoothstep(-0.65,0.45,cos(theta-0.3));
    float intensity = 0.001+0.68*arc*notch;
    float focus = pow(0.5+0.5*cos(theta+0.4),6.0);
    float width = mix(0.011,0.0023,focus) + aa;
    float outer = lightFold(distance,width);

    // Small red/blue offsets touch only the lower-right turn of the caustic.
    // The much stronger neutral focus keeps this from becoming a rainbow ring.
    float spectralGate = pow(clamp(0.5+0.5*cos(theta+0.65),0.0,1.0),10.0);
    float dispersion = 0.0018*spectralGate;
    float3 spectrum = float3(lightFold(distance-dispersion,width),outer,
                            lightFold(distance+dispersion,width));
    color += intensity*spectrum*float3(1.03,1.005,0.95);

    // A second, partial fold converges on the bright edge, then peels away.
    // Its slow change in separation is the visible effect of the glass turning.
    float innerDistance = distance+(0.021+0.009*breathe)*pow(1.0+cos(theta+0.15),2.0);
    float innerGate = pow(clamp(0.5-0.5*sin(theta-0.25),0.0,1.0),3.0);
    float inner = lightFold(innerDistance,0.013+0.009*(0.5+0.5*sin(theta))+aa);
    color += float3(0.20,0.190,0.165)*inner*innerGate;
    color += float3(0.039,0.045,0.049)*lightGaussian(distance-0.026,0.038)*arc;

    // A much softer internal fold connects the concentrated edge to the pool.
    // It is wide enough to merge into illumination rather than draw a third rim.
    float sheetDistance = q.y+0.045-0.45*q.x*q.x+0.014*breathe;
    float sheetX = (q.x-0.035)/0.24;
    float sheetX2 = sheetX*sheetX;
    float sheetGate = exp(-sheetX2*sheetX2);
    color += float3(0.055,0.055,0.047)*lightGaussian(sheetDistance,0.042)*sheetGate;

    // Keep the half-float artwork within SDR, preserving the native host's
    // color conversion and avoiding display-dependent clipped HDR patches.
    return float4(clamp(color,0.0,0.97),1.0);
}
