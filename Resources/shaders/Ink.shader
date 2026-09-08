#include <metal_stdlib>
using namespace metal;

// INK FINDING ITS SHAPE
// A single graphite drop on warm, uncoated paper. The black is held in a small
// connected reservoir; water travels farther, finding branching capillaries.
// Every mark is evaluated from position and Float time, so stopping the host's
// clock freezes an entirely resolved drawing. No history, textures or uniforms
// beyond fragment buffer 0 are needed.
struct InkVertex { float4 position [[position]]; float2 uv; };

vertex InkVertex vertex_main(uint id [[vertex_id]]) {
    float2 uv = float2(float((id << 1u) & 2u), float(id & 2u));
    return {float4(uv * 2.0 - 1.0, 0.0, 1.0), float2(uv.x, 1.0-uv.y)};
}

float inkHash(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float inkNoise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float2 u = f*f*(3.0-2.0*f);
    return mix(mix(inkHash(i), inkHash(i+float2(1,0)), u.x),
               mix(inkHash(i+float2(0,1)), inkHash(i+1.0), u.x), u.y);
}

float inkFbm(float2 p) {
    float sum = 0.0, weight = 0.53;
    for (int i=0; i<4; ++i) {
        sum += weight*inkNoise(p);
        p = float2(1.61*p.x-1.23*p.y, 1.23*p.x+1.61*p.y)+7.17;
        weight *= 0.48;
    }
    return sum;
}

// Distance to a gently bent, tapered channel. Axial distance closes each tip;
// distance to its curved centerline keeps the join with its parent continuous.
float inkChannel(float2 p, float2 start, float angle, float extent,
                 float width, float bend, float front) {
    float2 dir = float2(cos(angle), sin(angle));
    float2 q = float2(dot(p-start,dir), dot(p-start,float2(-dir.y,dir.x)));
    float s = clamp(q.x/extent, 0.0, 1.0);
    float curve = bend*s*s*(2.0-s);
    float tail = max(0.0,1.0-s);
    float w = width * (0.65*tail+0.35*sqrt(tail));
    // Local paper pores interrupt the smooth taper with a few wider pools.
    w *= 0.83+0.28*inkNoise(float2(s*7.0,angle*13.0));
    w *= 1.0-smoothstep(front-0.12,front,s);
    return max(abs(q.y-curve)-w, max(-q.x-width, q.x-extent*front));
}

fragment float4 fragment_main(InkVertex in [[stage_in]], constant float &time [[buffer(0)]]) {
    // Screen dimensions come from derivatives of our own interpolant. Framing
    // uses the shorter side and eases down slightly in portrait, preserving the
    // whole stain without requiring a resolution uniform from the native host.
    float2 pixel = float2(abs(dfdx(in.uv.x)), abs(dfdy(in.uv.y)));
    float aspect = pixel.y/pixel.x;
    float2 screen = float2(aspect,1.0)/min(aspect,1.0);
    float2 uv = in.uv;
    float2 center = float2(mix(0.485,0.425,smoothstep(0.85,1.45,aspect)),0.52);
    float2 p = (uv-center)*screen;
    float framing = mix(0.92,1.0,smoothstep(0.7,1.4,aspect));
    p /= framing;
    float aa = max(pixel.x*screen.x, pixel.y*screen.y)/framing;
    float t = max(0.0,time);
    float grain = inkHash(floor(in.position.xy));
    float paperCloud = inkFbm(p*7.0+57.0)-0.48;
    float fiberA = pow(inkNoise(float2(p.x*95.0+p.y*21.0,p.y*1380.0)),9.0);
    float fiberB = pow(inkNoise(float2(p.x*1210.0,p.y*81.0-p.x*14.0)),10.0);
    float paperRelief = paperCloud*0.021+(grain-0.5)*0.009+(fiberA+fiberB-0.04)*0.018;
    float3 paper = float3(0.862,0.829,0.746) + paperRelief;
    // Beyond this conservative bound the remaining wash is below one display
    // code value. Blank paper therefore avoids all of the channel evaluation.
    if (dot(p,p)>0.25) return float4(paper,1.0);

    // A bounded wet front: an initial opening, followed by very slow unequal
    // oscillations of local permeability. The clocks have no shared short loop,
    // and no sawtooth phase or frame boundary can cause a conspicuous reset.
    float opening = 0.74 + 0.26*(1.0-exp(-t/85.0));
    float seep = 0.5 + 0.20*sin(t*0.019) + 0.16*sin(t*0.0113+1.7);
    float2 warp = float2(inkFbm(p*16.0+3.7),inkFbm(p*16.0-19.1))-0.46;
    float fine = inkNoise(p*145.0+11.0);
    float2 q = p + warp*0.035 + (float2(fine,inkNoise(p*157.0-7.0))-0.5)*0.0016;
    float macro = inkFbm(p*21.0+4.0);

    // Unequal limbs form an intentionally asymmetric drawing. All originate in
    // the same reservoir. Their branching, taper and coarse meander are fixed
    // in the paper; only the reach of the wet front and pigment density evolve.
    const float4 limbs[8] = {
        float4(-2.80,0.193,0.014, 0.015),
        float4(-2.16,0.269,0.015,-0.048),
        float4(-1.43,0.159,0.012, 0.021),
        float4(-0.59,0.398,0.018,-0.066),
        float4(-0.08,0.301,0.013,-0.011),
        float4( 0.93,0.189,0.016,-0.023),
        float4( 1.79,0.153,0.018, 0.013),
        float4( 2.40,0.317,0.018,-0.047)
    };
    float channels = 1.0;
    float mainChannels = 1.0;
    float wet = 1.0;
    for (int i=0; i<8; ++i) {
        float4 arm = limbs[i];
        float phase = float(i)*1.83;
        float breathe = 1.0+0.075*sin(t*(0.0101+0.0007*float(i))+phase)
                           +0.035*sin(t*0.027+phase*2.1);
        float length = arm.y;
        float front = min(0.99,0.89*opening*breathe);
        float2 dir = float2(cos(arm.x),sin(arm.x));
        float2 normal = float2(-dir.y,dir.x);
        float main = inkChannel(q,float2(0),arm.x,length,arm.z,arm.w,front);
        channels = min(channels,main);
        mainChannels = min(mainChannels,main);
        // Five secondary capillaries meet a parent's curved centerline before
        // taking their own, finer route through the fibers.
        for (int j=0; j<5; ++j) {
            float s = 0.19+float(j)*0.135;
            float side = ((i+j)%2==0) ? -1.0 : 1.0;
            float2 start = dir*(length*s)+normal*(arm.w*s*s*(2.0-s));
            float a = arm.x+side*(0.55+0.09*float(j));
            float len = length*(0.39-0.031*float(j));
            float width = arm.z*(0.37-0.038*float(j));
            float childFront = clamp((front-s)/0.34,0.0,0.99);
            float child = inkChannel(q,start,a,len,width,side*0.014,childFront);
            channels = min(channels,max(child,(s-front)*length));
            float branchS = 0.38+0.035*float((i+j)%3);
            float2 twigStart = start+float2(cos(a),sin(a))*len*branchS
                              +float2(-sin(a),cos(a))*(side*0.014*branchS*branchS*(2.0-branchS));
            float twig = inkChannel(q,twigStart,a-side*0.64,len*0.48,width*0.37,-side*0.006,
                                    clamp((childFront-branchS)/0.5,0.0,0.99));
            channels = min(channels,max(twig,(branchS-childFront)*len));
        }
        // The two dominant limbs retain broad gray water pools. Smaller limbs
        // stay drier, avoiding the uniform halo of a blurred digital outline.
        float waterWidth = (i==3 || i==7) ? 3.8 : 1.5;
        wet = min(wet,inkChannel(q+warp*0.025,float2(0),arm.x,length,arm.z*waterWidth,arm.w,min(1.0,front+0.07)));
    }

    float2 c = q*float2(1.03,1.16) + warp*0.030;
    float reservoir = length(c) - (0.023 + 0.062*macro);
    float shape = min(reservoir, channels);

    // Fine branches split twice from the principal channels. A multiscale pore
    // field then carries their edges a little farther into the paper fibers.
    float pore = inkFbm(p*240.0+warp*2.8);
    // Elongated pores follow the two crossed fiber directions of the paper.
    // They make fine attached whiskers rather than a freestanding speckle ring.
    float2 paperFiber = p + (float2(inkNoise(p*145.0+19.0),inkNoise(p*161.0-3.0))-0.5)*0.004;
    float fiberField = mix(inkNoise(float2(paperFiber.x*780.0+paperFiber.y*230.0,paperFiber.y*205.0)),
                          inkNoise(float2(paperFiber.x*215.0,paperFiber.y*730.0-paperFiber.x*190.0)),
                          inkNoise(p*36.0+12.0));
    float fiberReach = 0.003+0.010*pore;
    float edge = shape + (pore-0.48)*0.0035 + (fine-0.5)*0.0015
                       -pow(fiberField,8.0)*0.0015;
    float body = 1.0-smoothstep(-aa,aa,edge);
    float hairs = smoothstep(0.62,0.87,fiberField)
                *(1.0-smoothstep(0.0,fiberReach,max(shape,0.0)));
    hairs *= smoothstep(-0.004,0.002,shape)*0.055;

    // A thin pale water stain extends past the black. Granulation separates
    // heavier graphite from the wash, giving pools a granular, matte interior.
    float wash = exp(-max(min(shape,wet+(pore-0.46)*0.009),0.0)*130.0);
    wash *= 0.09 + 0.43*macro;
    float distanceFromPool = smoothstep(0.075,0.37,length(q));
    float localPool = smoothstep(0.50,0.70,inkNoise(p*39.0+14.0));
    float deposit = 0.975 - 0.24*distanceFromPool + 0.15*localPool*distanceFromPool;
    float fineDeposit = 0.67 + 0.18*inkFbm(p*31.0+7.0) + 0.11*localPool;
    float fineOwnership = smoothstep(-0.004,0.004,min(mainChannels,reservoir));
    deposit = mix(deposit,fineDeposit,fineOwnership);
    float drift = inkNoise(p*24.0 + float2(sin(t*0.007),sin(t*0.0097))*0.35);
    deposit *= 0.96 + 0.033*drift + 0.025*seep;
    float pigment = clamp(body*deposit + hairs + wash*(1.0-body),0.0,0.98);
    float pool = 1.0-smoothstep(-0.037,0.009,reservoir);
    pigment = mix(pigment,0.980+0.01*fine,pool*0.88);

    // Paper is anchored to image coordinates, never animated: softly mottled
    // pulp, sparse crossing fibers, and subpixel grain. All RGB values are SDR
    // linear light, for the host's rgba16Float -> sRGB display conversion.
    float3 graphite = float3(0.014,0.017,0.018);
    float3 color = mix(paper,graphite,pigment);
    color += float3(0.011,0.010,0.008)*(grain-0.5)*pigment;
    return float4(clamp(color,0.0,1.0),1.0);
}
