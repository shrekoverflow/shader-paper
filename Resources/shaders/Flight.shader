#include <metal_stdlib>
using namespace metal;

// Flight — a quiet atlas of cloud, sun and small journeys.
// Original procedural artwork. No textures or external resources.
struct FlightVertex { float4 position [[position]]; float2 uv; };
vertex FlightVertex vertex_main(uint id [[vertex_id]]) {
    float2 uv = float2(float((id << 1u) & 2u), float(id & 2u));
    return { float4(uv * 2.0 - 1.0, 0.0, 1.0), uv };
}

float flightHash(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// Smooth procedural variation gives old contrails a little wind erosion.
float3 flightNoise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    float2 du = 30.0 * f * f * (f * (f - 2.0) + 1.0);
    float a = flightHash(i), b = flightHash(i + float2(1, 0));
    float c = flightHash(i + float2(0, 1)), d = flightHash(i + float2(1, 1));
    float k = a - b - c + d;
    return float3(a + (b-a)*u.x + (c-a)*u.y + k*u.x*u.y,
                  du.x * (b-a+k*u.y), du.y * (c-a+k*u.x));
}

float flightSegment(float2 p, float2 a, float2 b) {
    float2 e = b-a;
    return length(p-a-e*clamp(dot(p-a,e)/dot(e,e),0.0,1.0));
}
float flightTriangle(float2 p, float2 a, float2 b, float2 c) {
    float2 e0=b-a,e1=c-b,e2=a-c;
    float2 v0=p-a,v1=p-b,v2=p-c;
    float2 q0=v0-e0*clamp(dot(v0,e0)/dot(e0,e0),0.0,1.0);
    float2 q1=v1-e1*clamp(dot(v1,e1)/dot(e1,e1),0.0,1.0);
    float2 q2=v2-e2*clamp(dot(v2,e2)/dot(e2,e2),0.0,1.0);
    float s=sign(e0.x*e2.y-e0.y*e2.x);
    float2 d=min(min(float2(dot(q0,q0),s*(v0.x*e0.y-v0.y*e0.x)),
                      float2(dot(q1,q1),s*(v1.x*e1.y-v1.y*e1.x))),
                      float2(dot(q2,q2),s*(v2.x*e2.y-v2.y*e2.x)));
    return -sqrt(d.x)*sign(d.y);
}
float flightHull(float2 p) {
    float body = length(float2(p.x / 0.061, (p.y-0.055) / 0.68))-1.0;
    body *= 0.057;
    float2 q=float2(abs(p.x),p.y);
    float wing = min(flightTriangle(q,float2(0.035,0.15),float2(0.58,-0.14),float2(0.58,-0.205)),
                     flightTriangle(q,float2(0.035,0.15),float2(0.58,-0.205),float2(0.035,-0.10)));
    float winglet=flightSegment(q,float2(0.575,-0.165),float2(0.585,-0.10))-0.012;
    wing=min(wing,winglet);
    float tail = flightTriangle(q,float2(0.025,-0.355),float2(0.20,-0.56),float2(0.025,-0.58));
    float engine = length(float2((q.x-0.204)/0.037,(q.y+0.005)/0.108))-1.0;
    engine*=0.03;
    return min(min(body,wing),min(tail,engine));
}

float flightHash3(float3 p) {
    p=fract(p*0.1031);
    p+=dot(p,p.zyx+31.32);
    return fract((p.x+p.y)*p.z);
}
float flightVolumeNoise(float3 p) {
    float3 c=floor(p),f=fract(p);
    f=f*f*(3.0-2.0*f);
    return mix(mix(mix(flightHash3(c),flightHash3(c+float3(1,0,0)),f.x),
                   mix(flightHash3(c+float3(0,1,0)),flightHash3(c+float3(1,1,0)),f.x),f.y),
               mix(mix(flightHash3(c+float3(0,0,1)),flightHash3(c+float3(1,0,1)),f.x),
                   mix(flightHash3(c+float3(0,1,1)),flightHash3(c+float3(1,1,1)),f.x),f.y),f.z);
}
float flightDensity(float3 p) {
    float corridor=p.x*0.53+p.y*0.85;
    float bank=smoothstep(0.08,0.50,abs(sin(corridor*1.6+0.16*sin(p.x*2.3)))/1.6);
    float3 q=p*float3(4.3,4.3,3.5)+float3(5.8,1.5,13.0);
    float n=flightVolumeNoise(q)*0.50;
    n+=flightVolumeNoise(q*2.07+19.1)*0.25;
    n+=flightVolumeNoise(q*4.23+37.8)*0.125;
    n+=flightVolumeNoise(q*8.61+11.2)*0.0625;
    n+=flightVolumeNoise(q*17.43+63.1)*0.03125;
    n+=flightVolumeNoise(q*35.1+9.5)*0.015625;
    float vertical=abs(p.z-0.43);
    return max(n+bank*0.26-0.54-vertical*0.28,0.0)*smoothstep(0.02,0.18,p.z);
}
// Local civil time colors the atmosphere independently of the motion clock.
// The four weights form a smooth partition of unity, including at midnight.
struct FlightLighting {
    float3 skyDeep, skyGlow, skySlope;
    float3 cloudShadow, cloudLight, cloudRim;
    float3 aircraftTint, contrail, direction;
};
float3 flightMoodColor(float4 weights, float3 night, float3 dawn, float3 day, float3 dusk) {
    return night*weights.x + dawn*weights.y + day*weights.z + dusk*weights.w;
}
FlightLighting flightLighting(float localHour) {
    float hour = isfinite(localHour) ? fract(localHour / 24.0) * 24.0 : 12.0;
    float morning = smoothstep(6.25,8.0,hour);
    float evening = smoothstep(16.0,18.5,hour);
    float dawn = smoothstep(4.0,6.25,hour) * (1.0-morning);
    float day = morning * (1.0-evening);
    float dusk = evening * (1.0-smoothstep(18.5,21.0,hour));
    float4 weights=float4(max(1.0-dawn-day-dusk,0.0),dawn,day,dusk);
    FlightLighting light;
    light.skyDeep=flightMoodColor(weights,
        float3(0.004,0.009,0.023),float3(0.075,0.082,0.15),
        float3(0.14,0.30,0.445),float3(0.085,0.061,0.12));
    light.skyGlow=flightMoodColor(weights,
        float3(0.013,0.030,0.057),float3(0.39,0.235,0.265),
        float3(0.36,0.545,0.63),float3(0.48,0.225,0.105));
    light.skySlope=flightMoodColor(weights,
        float3(0.0003,0.0015,0.005),float3(0.025,0.004,-0.008),
        float3(0.03,0.018,-0.015),float3(0.030,0.008,-0.004));
    light.cloudShadow=flightMoodColor(weights,
        float3(0.009,0.021,0.047),float3(0.10,0.115,0.21),
        float3(0.25,0.39,0.52),float3(0.115,0.079,0.145));
    light.cloudLight=flightMoodColor(weights,
        float3(0.075,0.13,0.22),float3(0.84,0.515,0.425),
        float3(0.96,0.94,0.865),float3(0.90,0.49,0.225));
    light.cloudRim=flightMoodColor(weights,
        float3(0.012,0.025,0.045),float3(0.12,0.08,0.065),
        float3(0.13,0.115,0.085),float3(0.14,0.08,0.035));
    light.aircraftTint=flightMoodColor(weights,
        float3(0.24,0.36,0.53),float3(1.0,0.74,0.70),
        float3(1.0),float3(1.0,0.67,0.40));
    light.contrail=flightMoodColor(weights,
        float3(0.11,0.19,0.29),float3(0.87,0.66,0.63),
        float3(0.95,0.966,0.95),float3(0.94,0.65,0.37));
    light.direction=normalize(flightMoodColor(weights,
        float3(-0.55,0.45,0.85),float3(-1.0,0.30,0.43),
        float3(-0.65,0.65,1.0),float3(0.95,0.32,0.44)));
    return light;
}
float3 flightClouds(float3 sky, float2 p, float time, FlightLighting lighting) {
    float2 q=p+float2(time*0.00065,-time*0.00029);
    float transmission=1.0;
    float3 result=0.0;
    float3 sun=lighting.direction;
    // A bounded vertical volume integrates sunlit billows and translucent skirts.
    for (int step=0;step<19;++step) {
        float z=1.34-float(step)*0.073;
        float3 pos=float3(q+float2(0.14,-0.06)*z,z);
        float density=flightDensity(pos);
        if (density>0.0001 && transmission>0.008) {
            float shadow=flightDensity(pos+sun*0.13);
            float light=exp(-shadow*13.0);
            float rim=clamp(0.35+(density-shadow)*6.0,0.0,1.0);
            float3 shade=mix(lighting.cloudShadow,lighting.cloudLight,light*0.72+rim*0.28);
            shade+=lighting.cloudRim*rim;
            float alpha=1.0-exp(-density*3.28);
            result+=transmission*alpha*shade;
            transmission*=1.0-alpha;
        }
    }
    return result+sky*transmission;
}

fragment float4 fragment_main(FlightVertex in [[stage_in]], constant float &time [[buffer(0)]],
                              constant float &localHour [[buffer(1)]]) {
    float2 pixel = float2(length(dfdx(in.uv)),length(dfdy(in.uv)));
    float aspect = pixel.y / max(pixel.x,0.000001);
    float2 p=(in.uv-0.5)*float2(aspect,1.0);
    float aa = pixel.y;
    float t = max(time,0.0);
    FlightLighting lighting=flightLighting(localHour);
    float2 glowPosition=float2(lighting.direction.x*1.3583078,0.67);
    float sunlight = exp(-length((p-glowPosition)*float2(0.58,0.80))*1.2);
    float3 color = mix(lighting.skyDeep,lighting.skyGlow,sunlight*0.68);
    color += lighting.skySlope*p.y;
    color = flightClouds(color,p,t,lighting);

    // Independent lanes cross the view; complete trails wrap beyond its bounds.
    for (int i=0;i<11;++i) {
        float fi=float(i);
        float angle = 0.54 + (flightHash(float2(fi,43))-0.5)*0.45;
        if (i==3 || i==6) angle += 2.75;
        float2 forward=float2(sin(angle),cos(angle));
        float2 side=float2(forward.y,-forward.x);
        float travelExtent=aspect*abs(forward.x)+abs(forward.y)+2.1;
        float phase = fract(t*(0.0064+fi*0.00051)/travelExtent + fract(0.40+fi*0.091));
        float travel=(phase-0.5)*travelExtent;
        float lane=sin(fi*2.399)*min(aspect,1.8)*0.31;
        float curve=0.070*sin(travel*1.6+fi*2.0);
        float2 center = forward*travel + side*(lane+curve);
        float2 relative=p-center;
        float along=dot(relative,forward);
        float cross=dot(relative,side);
        float size=0.019+flightHash(float2(fi,87))*0.010;
        float lag=max(-along,0.0);
        float trailLength=0.46+flightHash(float2(fi,33))*0.35;
        if (along<0.0 && along>-trailLength && abs(cross)<0.12) {
            float pastTravel=travel+along;
            float curvePast=0.070*sin(pastTravel*1.6+fi*2.0);
            float wind = (sin(lag*16.0+fi*7.0+t*0.015)*0.5+sin(lag*41.0-fi*2.0)*0.18)*lag*0.011;
            float track=cross-(curvePast-curve)-wind;
            float spread=0.00040+lag*0.011;
            float engines=size*0.203;
            float a=exp(-pow((track-engines)/spread,2.0));
            float b=exp(-pow((track+engines)/spread,2.0));
            float born=smoothstep(size*0.27,size*1.7,lag);
            float die=pow(max(1.0-lag/trailLength,0.0),1.75);
            float breaks=0.82+0.18*flightNoise(float2(lag*60.0,fi*9.0+t*0.011)).x;
            float trail=(a+b)*born*die*breaks*0.41;
            color=mix(color,lighting.contrail,clamp(trail,0.0,0.54));
        }
        if (length(relative)<size*1.5) {
            float turn=atan(0.112*cos(travel*1.6+fi*2.0));
            float2 local=float2(cross*cos(turn)-along*sin(turn),cross*sin(turn)+along*cos(turn))/size;
            float edge=aa/size;
            float shadow=flightHull(local+float2(0.065,-0.09));
            color=mix(color,float3(0.12,0.22,0.32)*lighting.aircraftTint,0.17*(1.0-smoothstep(-edge,edge*2.0,shadow)));
            float hull=flightHull(local);
            float shape=1.0-smoothstep(-edge*0.65,edge*0.65,hull);
            float3 paint=mix(float3(0.27,0.44,0.56),float3(0.97,0.972,0.937),smoothstep(-0.13,0.018,-local.x));
            float body=1.0-smoothstep(0.035,0.072,abs(local.x));
            paint=mix(paint,float3(0.78,0.84,0.84),body*0.45);
            float spine=exp(-pow((local.x+0.018)/0.019,2.0))*body;
            paint+=float3(0.10,0.09,0.068)*spine;
            float cockpit=1.0-smoothstep(0.02,0.045,length((local-float2(0.0,0.578))*float2(1.0,0.58)));
            paint=mix(paint,float3(0.13,0.27,0.36),cockpit*0.8);
            float fin=1.0-smoothstep(edge,edge*2.0,flightSegment(local,float2(0.0,-0.48),float2(-0.01,-0.28))-0.013);
            paint=mix(paint,float3(0.32,0.53,0.62),fin*0.62);
            color=mix(color,paint*lighting.aircraftTint,shape);
        }
    }
    // Very gentle optical falloff keeps the center clear for the tiny aircraft.
    float vignette=dot(p/float2(max(aspect,1.0),1.0),p/float2(max(aspect,1.0),1.0));
    color*=1.0-0.07*vignette;
    return float4(clamp(color,0.0,1.0),1.0);
}
