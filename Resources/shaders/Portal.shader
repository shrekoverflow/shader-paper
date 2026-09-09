// Portal — the WorkOS mark, machined in magnesium.
// Logo geometry adapted from the official WorkOS mark: https://workos.com/.
// Original procedural materials, lighting and rendering. No image textures.
#include <metal_stdlib>
using namespace metal;

struct PortalVertex { float4 position [[position]]; float2 uv; };
vertex PortalVertex vertex_main(uint id [[vertex_id]]) {
    float2 uv = float2(float((id << 1u) & 2u), float(id & 2u));
    return {float4(uv * 2.0 - 1.0, 0.0, 1.0), uv};
}

// Accurate compact WorkOS mark distance. SVG shape from https://workos.com/.
// Circular fits replace tiny cubic corners; maximum fit error is 0.0155 SVG units.
// Inputs to portalMark are world coordinates: logo spans 2 units tall;
// y is upward. Top plane / extrusion depth handled by caller.
struct WOSClosest { float d2; float side; };
inline void wosCandidate(float2 p, float2 q, float2 n, thread WOSClosest &best) {
    float2 v=p-q;
    float d2=dot(v,v);
    if (d2<best.d2) { best.d2=d2; best.side=dot(v,n); }
}
inline void wosLine(float2 p,float2 a,float2 b,float2 na,float2 nb,thread WOSClosest &best) {
    float2 e=b-a;
    float t=dot(p-a,e)/dot(e,e);
    float2 n=t<=0.0 ? na : (t>=1.0 ? nb : float2(-e.y,e.x));
    wosCandidate(p,a+clamp(t,0.0,1.0)*e,n,best);
}
inline void wosArc(float2 p,float2 a,float2 b,float2 center,float radius,float2 bisector,float cosHalfAngle,float orientation,float2 na,float2 nb,thread WOSClosest &best) {
    float2 v=p-center;
    float l=length(v);
    if (dot(v,bisector)>=l*cosHalfAngle) {
        float2 radial=l>0.00001 ? v/l : bisector;
        wosCandidate(p,center+radius*radial,orientation*radial,best);
    } else {
        wosCandidate(p,a,na,best);
        wosCandidate(p,b,nb,best);
    }
}
inline float wosLobeSVG(float2 p) {
    WOSClosest best={1e20,1.0};
    wosArc(p, float2(0.40600000, 10.49600000), float2(0.40600000, 13.50500000), float2(2.99058621, 12.00050000), 2.99058625, float2(-1.00000000, 0.00000000), 0.86424065, 1.0, float2(-0.86513613, -0.50153711), float2(-0.86511065, 0.50158106), best);
    wosLine(p, float2(0.40600000, 13.50500000), float2(5.26200000, 21.91400000), float2(-0.86511065, 0.50158106), float2(-0.87460310, 0.48483958), best);
    wosArc(p, float2(5.26200000, 21.91400000), float2(12.14800000, 22.02500000), float2(8.73566547, 20.06713588), 3.93411475, float2(-0.01611757, 0.99987010), 0.48361865, 1.0, float2(-0.87460310, 0.48483958), float2(0.86675379, 0.49873628), best);
    wosLine(p, float2(12.14800000, 22.02500000), float2(13.32000000, 19.99400000), float2(0.86675379, 0.49873628), float2(0.99999984, -0.00056351), best);
    wosLine(p, float2(13.32000000, 19.99400000), float2(8.69500000, 12.00000000), float2(0.99999984, -0.00056351), float2(0.99999984, -0.00057062), best);
    wosLine(p, float2(8.69500000, 12.00000000), float2(14.75100000, 1.50500000), float2(0.99999984, -0.00057062), float2(0.86563278, 0.50067942), best);
    wosArc(p, float2(14.75100000, 1.50500000), float2(16.12600000, 0.00000000), float2(18.88628161, 3.90246658), 4.78000000, float2(-0.73827306, -0.67450196), 0.97700061, -1.0, float2(0.86563278, 0.50067942), float2(0.95299937, -0.30297227), best);
    wosLine(p, float2(16.12600000, 0.00000000), float2(8.59400000, 0.00000000), float2(0.95299937, -0.30297227), float2(0.00076785, -0.99999971), best);
    wosArc(p, float2(8.59400000, 0.00000000), float2(5.40000000, 1.84600000), float2(8.58835413, 3.67640471), 3.67640904, float2(-0.50039501, -0.86579722), 0.86502774, 1.0, float2(0.00076785, -0.99999971), float2(-0.86663850, -0.49893658), best);
    wosLine(p, float2(5.40000000, 1.84600000), float2(0.40600000, 10.49600000), float2(-0.86663850, -0.49893658), float2(-0.86513613, -0.50153711), best);
    return sqrt(best.d2)*(best.side<0.0 ? -1.0 : 1.0);
}
inline float portalMark(float2 xy) {
    float2 p=float2(13.846+12.0*xy.x,12.0-12.0*xy.y);
    float a=wosLobeSVG(p);
    float b=wosLobeSVG(float2(27.692,24.0)-p);
    return min(a,b)/12.0;
}


static float portalSolid(float3 p) {
    // A planar machined chamfer with tiny radiused transitions. The outer
    // sidewall remains the approved SVG silhouette.
    float2 q = float2(portalMark(p.xy), abs(p.z - 0.175) - 0.175);
    float box = max(q.x,q.y);
    float chamfer = (q.x+q.y+0.014)*0.70710678;
    float h = max(0.003-abs(box-chamfer),0.0)/0.003;
    return max(box,chamfer)+h*h*0.00075;
}

static float3 portalNormal(float3 p) {
    const float e=0.0002;
    return normalize(float3(
        portalSolid(p+float3(e,0,0))-portalSolid(p-float3(e,0,0)),
        portalSolid(p+float3(0,e,0))-portalSolid(p-float3(0,e,0)),
        portalSolid(p+float3(0,0,e))-portalSolid(p-float3(0,0,e))));
}

static float portalHash(float2 p) {
    float3 q = fract(float3(p.x, p.y, p.x) * float3(0.1031, 0.1030, 0.0973));
    q += dot(q, q.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}

// Value and analytic gradient. Band limiting keeps the finish quiet when small.
// Every grain stays attached to the moving material; no animated noise.
static float3 portalNoise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f), du = 6.0 * f * (1.0 - f);
    float a = portalHash(i), b = portalHash(i + float2(1, 0));
    float c = portalHash(i + float2(0, 1)), d = portalHash(i + float2(1, 1));
    float k = a - b - c + d;
    return float3(a + (b - a) * u.x + (c - a) * u.y + k * u.x * u.y,
                  du.x * (b - a + k * u.y), du.y * (c - a + k * u.x));
}

static float portalCard(float3 p, float3 r, float3 center, float2 size, float roughness) {
    float3 axis = normalize(center);
    float3 u = normalize(cross(float3(0, 1, 0), axis)), v = cross(axis, u);
    float cosine = dot(r, axis);
    if (cosine <= 0.025) return 0.0;
    float distance = dot(center - p, axis) / cosine;
    if (distance <= 0.0) return 0.0;
    float3 hit = p + r * distance - center;
    float2 q = abs(float2(dot(hit, u), dot(hit, v)));
    float blur = 0.06 + roughness * distance * 1.5;
    float2 edge = 1.0 - smoothstep(size - blur, size + blur, q);
    // Approximate the energy lost as a small emitter spreads through the
    // satin reflection lobe. Narrow lights must not brighten the whole face.
    float2 energy = min(float2(1.0),size/blur);
    return edge.x * edge.y * energy.x * energy.y;
}

static float portalLightSweep(float t) {
    // Two unhurried arcs keep reflections moving through a turn's reversal.
    // Source brightness stays constant: the light travels, never pulses.
    return sin(t * 0.074) + 0.16 * sin(t * 0.163);
}

static float portalDaylight(float localHour) {
    // Local civil time is independent of saved animation time. Broad dawn
    // and dusk transitions keep the once-per-minute held frame refresh quiet.
    float hour = isfinite(localHour) ? fract(localHour/24.0)*24.0 : 12.0;
    return smoothstep(6.5,9.0,hour)*(1.0-smoothstep(17.0,20.5,hour));
}

static float3 portalDayKey(float t) {
    // One window sets both the reflected highlight and the cast shadow.
    return float3(-2.6+0.45*portalLightSweep(t),2.7,3.8);
}

static float3 portalLightField(float2 p, float t, float blur) {
    // A travelling, softly folded ribbon of light. The same field illuminates
    // the floor and the reflected ceiling, tying the color washes together.
    float drift = 1.35*sin(t*0.15-0.7) + 0.22*sin(t*0.071);
    float fold = p.x - 0.40*p.y - drift + 0.14*sin(p.y*1.7+t*0.083);
    float width = 0.43 + blur;
    float core = exp(-pow(fold/width,2.0));
    float halo = exp(-pow(fold/(1.10+blur),2.0));
    float lower = exp(-pow(max(p.y+0.40,0.0)*1.25,2.0));
    float blueFold = p.x + 0.32*p.y - 2.35 - 0.55*sin(t*0.113+1.4);
    float blue = exp(-pow(blueFold/(0.48+blur),2.0));
    float upper = exp(-pow((p.y-2.7)/(0.65+blur),2.0))
                * exp(-pow((p.x+0.8*sin(t*0.067))/2.5,2.0));
    float3 light = float3(0.0020,0.0022,0.0040);
    light += lower*(float3(0.16,0.065,0.34)*halo + float3(3.2,1.05,1.70)*core);
    light += float3(0.12,0.22,0.78)*blue*(0.25+0.75*lower);
    light += float3(0.11,0.09,0.19)*upper;
    // Soften the broad wash; the separate grazing accent lights retain
    // their original color, brightness, and movement throughout the day.
    return light*0.62;
}

static float3 portalStudio(float3 p, float3 r, float roughness, float t, float daylight) {
    // A directional window and restrained fill give daytime silver a clear
    // bright-to-dark reflection. The nighttime studio retains its dim fill.
    float3 sky = mix(float3(0.005,0.0055,0.008),float3(0.025,0.028,0.035),daylight);
    float sweep = portalLightSweep(t);
    float3 nightKey = float3(0.014,0.015,0.02) * portalCard(p, r,
        float3(-3.4 + 1.7*sweep, 2.4, 5.0), float2(3.4, 4.0), roughness);
    float3 dayKey = float3(1.65,1.64,1.60) * portalCard(p, r,
        portalDayKey(t),float2(1.25,2.4),roughness*0.60);
    sky += mix(nightKey,dayKey,daylight);
    float ceilingDistance = (3.8-p.z)/max(r.z,0.15);
    float2 ceiling = (p.xy+r.xy*ceilingDistance)*0.72-float2(0,0.10);
    sky += portalLightField(ceiling,t,roughness*0.9)
         * smoothstep(0.02,0.35,r.z)*0.72;
    // Bright rose and blue cards are finite sources. Their reflections
    // catch individual edges, leaving stretches of dark metal between.
    sky += float3(2.8,0.92,1.75) * portalCard(p, r,
        float3(-4.5, -1.4+0.4*sin(t*0.067), 1.7), float2(1.25, 3.8), roughness);
    sky += float3(0.34,0.55,1.50) * portalCard(p, r,
        float3(4.0, 1.0, 2.8), float2(0.65, 3.5), roughness);
    sky += float3(0.012,0.005,0.017) * portalCard(p, r,
        float3(0.0, -4.0, 4.0), float2(3.6, 1.4), roughness);
    sky += mix(float3(0.07,0.065,0.11),float3(0.12,0.13,0.16),daylight) * portalCard(p, r,
        float3(-0.8, 5.0, 3.3), float2(3.5, 0.8), roughness);
    // A broad negative-fill flag moves across the reflected field, so the
    // studio sweep travels over the sculpture instead of pulsing exposure.
    sky *= 1.0-0.42*portalCard(p,r,float3(2.8+2.2*sweep,3.0,5.0),float2(1.2,4.5),roughness+0.08);
    // A dark studio flag gives the opposite face a charcoal reflection;
    // a slim white source traces a few polished edges through that contrast.
    sky *= 1.0-daylight*0.62*portalCard(p,r,float3(2.0,1.8,4.0),float2(1.0,3.8),roughness*0.45);
    sky += daylight*float3(1.5,1.48,1.43)*portalCard(p,r,
        float3(1.6,3.8,1.8),float2(0.18,2.4),roughness);
    // Ground reflected in the satin walls: a broad illuminated pool, broken
    // by dark flags. The reflection wraps continuously around the terminals.
    float floorWeight = 1.0-smoothstep(-0.5, 0.05, r.z);
    float2 floorHit = p.xy + r.xy * (p.z + 0.22)/max(-r.z, 0.15);
    float flag = smoothstep(-0.6, 0.0, r.x) * (1.0-smoothstep(0.3, 0.8, r.x));
    float wrap = pow(max(dot(normalize(r.xy+float2(0.0001)), normalize(float2(-0.8+0.22*sweep,-0.6))),0.0), 7.0);
    float3 floorColor = portalLightField(floorHit,t,roughness)*0.50*(1.0-0.7*flag);
    floorColor += mix(float3(0.004,0.004,0.006),float3(0.08,0.085,0.095),daylight)*(1.0-0.55*flag);
    floorColor += float3(1.2,0.38,0.78)*wrap;
    float blueWrap = pow(max(dot(normalize(r.xy+float2(0.0001)),
        normalize(float2(0.9,-0.38+0.15*sin(t*0.067)))),0.0),12.0);
    floorColor += float3(0.09,0.18,0.55)*blueWrap;
    float backPool = pow(max(dot(normalize(r.xy+float2(0.0001)),normalize(float2(-0.45,0.9))),0.0),5.0);
    floorColor += float3(0.23,0.21,0.37)*backPool;
    return mix(sky, floorColor, floorWeight);
}

// turn = (cos(angle), sin(angle)); negate y for the inverse rotation.
static float2 portalRotate(float2 p, float2 turn) {
    return float2(turn.x*p.x-turn.y*p.y,turn.y*p.x+turn.x*p.y);
}

static float3 portalMetal(float3 p, float3 n, float3 view, float t, float footprint, float2 turn, float daylight) {
    float face = smoothstep(0.97, 0.9995, n.z);
    float wall = 1.0 - smoothstep(0.02, 0.25, abs(n.z));
    float bevel = (1.0 - face) * (1.0 - wall);
    float mediumFilter = exp(-pow(footprint * 340.0, 2.0));
    float fineFilter = exp(-pow(footprint * 510.0, 2.0));
    // Domain-warped relief avoids a regular value-noise grid. Grain modulates
    // surface normals and roughness, rather than painting speckles on silver.
    float3 warp = portalNoise(p.xy*63.0);
    float3 grain = portalNoise(p.xy * 340.0 + warp.yz*0.37);
    float3 fine = portalNoise(p.xy * 510.0 + grain.yz*0.24 + float2(37.2, 8.6));
    float2 slopes = grain.yz*mediumFilter*0.075 + fine.yz*fineFilter*0.035;
    float3 toolRelief = portalNoise(float2(p.z*440.0,dot(p.xy,float2(0.8,0.6))*24.0));
    // Grazing walls cover more material per pixel. Filter the tool feed
    // in that projected footprint as the camera and sculpture move.
    float wallFootprint = footprint/max(abs(dot(n,view)),0.20);
    float toolBand = exp(-pow(wallFootprint*300.0,2.0));
    n = normalize(n + float3(slopes*face,wall*toolRelief.y*0.055*toolBand));
    float roughness = mix(0.22, 0.34, face);
    roughness = mix(roughness, 0.065, bevel);
    roughness += face*(grain.x-0.5)*0.065*mediumFilter;
    float3 reflected = reflect(-view, n);
    // Grain stays in object space; the room and its colored cards stay in
    // world space. Turning metal therefore moves through its reflections.
    float3 worldP = float3(portalRotate(p.xy,turn),p.z);
    float3 worldN = float3(portalRotate(n.xy,turn),n.z);
    float3 worldR = float3(portalRotate(reflected.xy,turn),reflected.z);
    float3 color = portalStudio(worldP, worldR, roughness, t, daylight)*float3(0.76,0.77,0.79);
    // Slim studio strips trace the polished chamfers with bright rose and
    // cool-lavender glints. The blasted face scatters these accents broadly
    // and weakly, preserving its satin finish instead of a painted-on rim.
    float silver = portalCard(worldP, worldR,
        float3(-3.8+0.45*sin(t*0.097), -2.6, 2.2+0.35*sin(t*0.071)),
        float2(0.26, 2.8), roughness);
    float lavender = portalCard(worldP, worldR,
        float3(3.6, 1.5+0.55*sin(t*0.083), 1.25),
        float2(0.20, 2.5), roughness);
    float accentFinish = 0.015*face + 0.38*wall + bevel;
    color += accentFinish*(float3(3.7,1.6,2.7)*silver + float3(1.4,1.5,3.5)*lavender);
    // Daytime jewelry lights: warm silver on the near chamfer and a cool
    // blue reflection along the far cut wall. Their small size keeps the
    // satin faces neutral while the polished edges catch distinct glints.
    float daySilver = portalCard(worldP,worldR,
        float3(-3.8,0.4+0.24*sin(t*0.087),1.4),float2(0.26,2.2),roughness);
    float dayBlue = portalCard(worldP,worldR,
        float3(4.0,-2.4+0.28*sin(t*0.079),1.5),float2(0.36,2.6),roughness);
    float dayAccentFinish = daylight*(0.006*face+0.65*wall+1.2*bevel);
    color += dayAccentFinish*(float3(3.0,2.85,2.65)*daySilver+float3(0.7,1.15,2.8)*dayBlue);
    float3 key = normalize(mix(float3(-3.4+1.7*portalLightSweep(t),2.4,5.0),portalDayKey(t),daylight));
    color += mix(float3(0.004,0.004,0.006),float3(0.045),daylight)*max(dot(worldN,key),0.0)*face;
    // The blasted finish scatters the large source with a shallow spatial
    // falloff. Microfacets facing the grazing strip carry the fine relief.
    float grazing = max(dot(worldN,normalize(float3(-4,2,1.4))),0.0);
    color += face*mix(float3(0.007,0.006,0.012),float3(0.055),daylight)*grazing;
    color *= 1.0-face*0.055*(1.0-grain.x)*mediumFilter;
    color *= 1.0-0.23*face;
    // Irregular fine tool feed on the walls. No periodic horizontal bands.
    float tooling = portalNoise(float2(p.z*780.0, dot(p.xy,float2(0.8,0.6))*48.0)).x-0.5;
    color *= 1.0 + wall*tooling*0.08*exp(-pow(wallFootprint*450.0,2.0));
    color *= mix(mix(0.48,0.32,daylight),1.0,smoothstep(0.0,0.09,p.z));
    return color;
}

static float3 portalGround(float2 p, float t, float footprint, float2 turn, float daylight) {
    float2 worldP = portalRotate(p,turn);
    float d = portalMark(p);
    float shadow = 0.0;
    if (d < 0.65) {
        // Integrate visibility of a finite area emitter at the extrusion top.
        // Multiple blockers along each ray keep the aperture shadows coherent.
        for (int i=0; i<12; ++i) {
            // Trade emitter samples for height samples under the smaller day
            // window: six rays × eight heights instead of twelve × four.
            // Crossfade the spare rays through dawn and dusk without a jump.
            float rayWeight = (i & 1) != 0 ? 1.0-daylight : 1.0;
            if (rayWeight == 0.0) continue;
            float angle = float(i)*2.399963;
            float radius = sqrt((float(i)+0.5)/12.0);
            float3 dayKey = portalDayKey(t);
            float2 slope = mix(float2(-0.68+0.34*portalLightSweep(t),0.48),dayKey.xy/dayKey.z,daylight)
                         + float2(cos(angle),sin(angle))*radius*mix(0.65,0.36,daylight);
            slope = portalRotate(slope,float2(turn.x,-turn.y));
            float blocked = 0.0;
            for (int j=1;j<=8;++j) {
                // Daylight's stronger shadows need intermediate height probes
                // to avoid layered edges. Fade those in with the window light;
                // the even probes are the exact original nighttime sampling.
                float weight = (j & 1) != 0 ? daylight : 1.0;
                if (weight == 0.0 || ((i & 1) != 0 && (j & 1) != 0)) continue;
                float h = float(j)*0.04375;
                float softness = 0.012+h*0.18;
                blocked=max(blocked,weight*(1.0-smoothstep(-softness,softness,portalMark(p+slope*h))));
            }
            shadow += blocked*rayWeight/(12.0-6.0*daylight);
        }
    }
    float contact = exp(-max(d,0.0)/0.018);
    float3 light = portalLightField(worldP,t,0.12);
    float2 windowPool = worldP-float2(-1.6,1.7);
    float pool = exp(-dot(windowPool,windowPool)*0.20);
    float2 windowUV = float2(dot(windowPool,float2(0.75,0.66)),dot(windowPool,float2(-0.66,0.75)));
    float dayPool = exp(-pow(windowUV.x/1.8,2.0)-pow(windowUV.y/4.0,2.0));
    float3 nightRoom = float3(0.006,0.0065,0.009)*(0.75+0.45*pool);
    float3 dayRoom = float3(0.07,0.075,0.085)+float3(0.52,0.515,0.50)*dayPool;
    light += mix(nightRoom,dayRoom,daylight);
    light *= 1.0-mix(0.58,0.78,daylight)*shadow;
    light *= 1.0-mix(0.72,0.85,daylight)*contact;
    // Short, blurred reflection close to the object, never a mirror floor.
    float reflection = exp(-max(d,0.0)/0.06)*(1.0-contact);
    light += reflection*portalLightField(worldP,t,0.25)*0.08;
    float3 grain = portalNoise(worldP*270.0);
    float texture = (grain.x-0.5)*exp(-pow(footprint*270.0,2.0));
    texture += (portalNoise(worldP*91.0+grain.yz*0.2).x-0.5)*0.45*exp(-pow(footprint*91.0,2.0));
    return light*(1.0+texture*0.045);
}

static float3 portalRender(float2 uv, float aspect, float pixelHeight, float t, float daylight) {
    // A shallow product-camera arc reveals the cut faces and carries
    // colored reflections around the chamfers. The mark turns on the floor;
    // Both camera and rigid turn use saved shader time, with no drift.
    // Portrait layouts retain the complete sculpture.
    float height = 2.70 / min(1.0, aspect / 1.18);
    float2 screen = (uv - 0.5) * float2(aspect, 1.0);
    float3 view = normalize(float3(0.17*sin(t*0.061)+0.018*sin(t*0.137),
                                  -0.58+0.067*sin(t*0.053), 1.0));
    float3 right = normalize(cross(float3(0,1,0),view)), up = cross(view, right);
    float3 ro = view * 7.5 - up * 0.045;
    float3 rd = normalize(-view * (7.5 / height) + right * screen.x + up * screen.y);
    // A restrained turntable gesture: both lobes move as one rigid mark.
    // Inverse-transform rays for the exact existing silhouette and extrusion.
    // A small secondary sway avoids a mechanical back-and-forth. The total
    // turn stays below ten degrees, keeping the silhouette easy to read.
    float angle = 0.145*sin(t*0.11)+0.024*sin(t*0.23);
    float2 turn = float2(cos(angle),sin(angle));
    float2 inverseTurn = float2(turn.x,-turn.y);
    ro.xy = portalRotate(ro.xy,inverseTurn);
    rd.xy = portalRotate(rd.xy,inverseTurn);
    float footprint = pixelHeight * height;
    float floorT = -ro.z / rd.z, topT = (0.350 - ro.z) / rd.z;
    float3 top = ro + rd * topT;
    float planar = portalMark(top.xy);
    float3 color;
    if (planar < -0.018) {
        color = portalMetal(top, float3(0, 0, 1), -rd, t, footprint, turn, daylight);
    } else {
        float travel = topT;
        bool hit = false;
        if (planar < 0.02 + 0.350 * length(rd.xy) / abs(rd.z)) {
            for (int i = 0; i < 56; ++i) {
                float distance = portalSolid(ro + rd * travel);
                if (distance < 0.00014) { hit = true; break; }
                travel += max(distance * 0.90, 0.0001);
                if (travel >= floorT) break;
            }
        }
        if (hit && travel < floorT) {
            float3 p = ro + rd * travel;
            color = portalMetal(p, portalNormal(p), -rd, t, footprint, turn, daylight);
        } else {
            color = portalGround((ro + rd * floorT).xy, t, footprint, turn, daylight);
        }
    }
    // A low, source-colored scattering halo softens the brightest lit edges.
    // Its strength follows the travelling light field, so dark edges stay dark.
    float2 worldTop = portalRotate(top.xy,turn);
    float edgeHalo = exp(-abs(planar)/0.07)*0.035;
    color += portalLightField(worldTop,t,0.28)*edgeHalo;
    // Gentle photographic shoulder in linear light. Display conversion
    // supplies the sRGB transfer, with headroom for polished highlights.
    return color / (0.72 + color);
}

fragment float4 fragment_main(PortalVertex in [[stage_in]], constant float &time [[buffer(0)]],
                              constant float &localHour [[buffer(1)]]) {
    float2 pixel = float2(length(dfdx(in.uv)), length(dfdy(in.uv)));
    float aspect = pixel.y / max(pixel.x, 1e-8);
    float t = max(time, 0.0);
    float daylight = portalDaylight(localHour);
    float3 color = portalRender(in.uv, aspect, pixel.y, t, daylight);
    float contrast = max(length(dfdx(color)), length(dfdy(color)));
    if (contrast > 0.025) {
        float3 refined = float3(0);
        for (int y = 0; y < 2; ++y) {
            for (int x = 0; x < 2; ++x) {
                float2 offset = (float2(x, y) - 0.5) * pixel * 0.5;
                refined += portalRender(in.uv + offset, aspect, pixel.y, t, daylight) * 0.25;
            }
        }
        color = mix(color, refined, smoothstep(0.025, 0.06, contrast));
    }
    float dither = portalHash(in.position.xy) - 0.5;
    return float4(clamp(color + dither * 0.00065, 0.0, 1.0), 1.0);
}
