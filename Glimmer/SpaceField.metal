//
//  SpaceField.metal
//
//  The app's space, behind onboarding and Home: a Schwarzschild black hole, ray traced in 3D every
//  frame. Photons leave the camera and bend by the hole's gravity (the
//  "starless" form of the null geodesic: x'' = -3/2 h² x / r⁵, in Schwarzschild
//  radii). The paths are traced once per frame into a lensing map (see
//  traceLensing), and each pixel reads its own photon's path from it. Where the photon crosses the disk plane it picks up
//  the accretion disk's light, Doppler-beamed and gravitationally redshifted;
//  where it escapes it sees a sky of stars and the galaxy's band; where it falls
//  in it sees nothing. The lensed far side of the disk, the photon ring and the
//  shadow all come out of the physics. Nothing here is drawn as a 2D shape.
//
//  The camera is computed in Swift (StageCamera) and passed in as a basis, so
//  the overlay's projected nodes and this field share one camera.
//

#include <metal_stdlib>
using namespace metal;

// The disk's inner and outer edge, in Schwarzschild radii (ISCO sits at 3).
constant float diskInner = 2.6;
constant float diskOuter = 12.0;

static float hash31(float3 p) {
    p = fract(p * 0.1031);
    p += dot(p, p.zyx + 31.32);
    return fract((p.x + p.y) * p.z);
}

static float3 hash33(float3 p) {
    p = fract(p * float3(0.1031, 0.1030, 0.0973));
    p += dot(p, p.yxz + 33.33);
    return fract((p.xxy + p.yxx) * p.zyx);
}

static float noise3(float3 p) {
    float3 i = floor(p);
    float3 f = fract(p);
    float3 u = f * f * (3.0 - 2.0 * f);
    float a = hash31(i);
    float b = hash31(i + float3(1, 0, 0));
    float c = hash31(i + float3(0, 1, 0));
    float d = hash31(i + float3(1, 1, 0));
    float e = hash31(i + float3(0, 0, 1));
    float g = hash31(i + float3(1, 0, 1));
    float h = hash31(i + float3(0, 1, 1));
    float k = hash31(i + float3(1, 1, 1));
    return mix(mix(mix(a, b, u.x), mix(c, d, u.x), u.y),
               mix(mix(e, g, u.x), mix(h, k, u.x), u.y), u.z);
}

static float fbm3(float3 p, int octaves) {
    float sum = 0.0;
    float amp = 0.5;
    for (int i = 0; i < octaves; i++) {
        sum += amp * noise3(p);
        p = p * 2.07 + float3(13.1, 7.7, 3.3);
        amp *= 0.5;
    }
    return sum;
}

/// One star layer on the celestial sphere: at most one star per cell, a soft
/// Gaussian at least a traced pixel wide, so a star never flickers between
/// pixels as the camera drifts. Stars hold steady: no twinkle.
static float3 starLayer(float3 dir, float scale, float density, float brightness, float size) {
    float3 p = dir * scale;
    float3 cell = floor(p);
    float3 h = hash33(cell);
    if (h.x > density) { return float3(0.0); }
    float3 star = cell + 0.25 + 0.5 * hash33(cell + 17.0);
    float3 off = star - p;
    off -= dir * dot(off, dir);
    float radius = size * (0.8 + 0.4 * h.y);
    float glow = exp(-dot(off, off) / (radius * radius));
    float3 tint = mix(float3(0.62, 0.76, 1.0), float3(1.0, 0.80, 0.58), h.z);
    return tint * glow * brightness * (0.25 + 0.75 * h.y * h.y);
}

/// Deep space without its stars: a dusty galactic band and faint nebulae. It
/// never changes, so it is baked once into a cube map (bakeSky).
static float3 nebulae(float3 dir) {
    float3 col = float3(0.0006, 0.0008, 0.0018);
    float3 bandNormal = normalize(float3(0.35, 0.86, -0.37));
    float band = exp(-pow(dot(dir, bandNormal) / 0.24, 2.0));
    float dust = fbm3(dir * 3.0, 5);
    float clouds = fbm3(dir * 8.0 + 4.0, 4);
    float lanes = smoothstep(0.48, 0.72, fbm3(dir * 5.5 + 11.0, 4));
    col += band * (float3(0.020, 0.024, 0.040) * dust + float3(0.050, 0.036, 0.028) * pow(clouds, 3.0)) * (1.0 - 0.8 * lanes);
    float nebula = fbm3(dir * 1.7 + 2.0, 4);
    col += float3(0.012, 0.007, 0.024) * pow(nebula, 3.0) * 3.0;
    col += float3(0.004, 0.012, 0.020) * pow(fbm3(dir * 2.4 + 7.0, 3), 4.0) * 3.0;
    return col;
}

/// Where an escaped photon came from: the baked nebulae plus stars, which stay
/// procedural so each one is sharp at any size. `stars` dims stars that the
/// lens stretches into long arcs, so a star behind the hole never draws a ring.
static float3 sky(float3 dir, texturecube<float> baked, float stars) {
    constexpr sampler linear(filter::linear);
    float3 col = baked.sample(linear, dir).rgb;
    col += (starLayer(dir, 260.0, 0.10, 0.34, 0.16) + starLayer(dir, 110.0, 0.05, 0.75, 0.08)) * stars;
    return col;
}

/// The direction through one texel of a cube face, in Metal's face order (+X, -X, +Y, -Y, +Z, -Z).
static float3 cubeDirection(uint face, float2 uv) {
    switch (face) {
    case 0: return normalize(float3(1.0, -uv.y, -uv.x));
    case 1: return normalize(float3(-1.0, -uv.y, uv.x));
    case 2: return normalize(float3(uv.x, 1.0, uv.y));
    case 3: return normalize(float3(uv.x, -1.0, -uv.y));
    case 4: return normalize(float3(uv.x, -uv.y, 1.0));
    default: return normalize(float3(-uv.x, -uv.y, -1.0));
    }
}

/// Bakes the nebulae once at launch.
kernel void bakeSky(texturecube<float, access::write> sky [[texture(0)]], uint3 id [[thread_position_in_grid]]) {
    uint size = sky.get_width();
    if (id.x >= size || id.y >= size || id.z >= 6) { return; }
    float2 uv = (float2(id.xy) + 0.5) / float(size) * 2.0 - 1.0;
    sky.write(float4(nebulae(cubeDirection(id.z, uv)), 1.0), id.xy, id.z);
}

/// Blackbody-like colour for a disk temperature (1 is the inner edge at rest).
static float3 heat(float t) {
    float3 ember = float3(0.50, 0.10, 0.015);
    float3 orange = float3(1.00, 0.42, 0.09);
    float3 gold = float3(1.00, 0.74, 0.42);
    float3 white = float3(1.00, 0.94, 0.86);
    float3 blue = float3(0.76, 0.85, 1.00);
    float3 c = mix(ember, orange, smoothstep(0.15, 0.45, t));
    c = mix(c, gold, smoothstep(0.45, 0.75, t));
    c = mix(c, white, smoothstep(0.75, 1.05, t));
    return mix(c, blue, smoothstep(1.15, 1.7, t));
}

/// The disk pattern's row for a log radius, across the disk's span.
static float diskRow(float logR) {
    float lo = log(diskInner * 0.9);
    float hi = log(diskOuter);
    return (logR - lo) / (hi - lo);
}

/// Bakes the disk's turbulence once at launch: x runs around the disk, y out
/// from its inner edge in log radius. The disk's orbit turns it at draw time.
kernel void bakeDisk(texture2d<float, access::write> pattern [[texture(0)]], uint2 id [[thread_position_in_grid]]) {
    if (id.x >= pattern.get_width() || id.y >= pattern.get_height()) { return; }
    float angle = (float(id.x) + 0.5) / float(pattern.get_width()) * 2.0 * M_PI_F;
    float lo = log(diskInner * 0.9);
    float logR = mix(lo, log(diskOuter), (float(id.y) + 0.5) / float(pattern.get_height()));
    float3 around = float3(cos(angle), sin(angle), logR);
    // Domain warping folds the turbulence into clumps and wisps of gas.
    float3 warp = float3(fbm3(around * float3(2.2, 2.2, 5.0), 4), fbm3(around * float3(2.2, 2.2, 5.0) + 9.1, 4), 0.0);
    float body = fbm3(around * float3(1.7, 1.7, 6.5) + warp * 1.6, 5);
    float fine = fbm3(around * float3(5.0, 5.0, 22.0) + warp * 0.8, 4);
    pattern.write(float4(body, fine, 0.0, 0.0), id);
}

/// The disk's light and opacity where a photon crosses its plane. The gas
/// orbits at Kepler speed, so the inner rings shear past the outer ones; the
/// side swinging toward the camera is boosted and bluer, the far side dimmer.
static float4 disk(float3 hit, float3 rayDir, float time, texture2d<float> pattern) {
    constexpr sampler wrap(filter::linear, mip_filter::linear, s_address::repeat, t_address::clamp_to_edge);
    float r = length(hit.xz);
    if (r < diskInner * 0.9 || r > diskOuter) { return float4(0.0); }
    float omega = sqrt(0.5 / (r * r * r));
    float logR = log(r);
    float angle = atan2(hit.z, hit.x) - omega * time * 5.0 + logR * 1.3;
    float2 turbulence = pattern.sample(wrap, float2(angle / (2.0 * M_PI_F), diskRow(logR))).rg;
    float body = turbulence.r;
    float fine = turbulence.g;
    // Bright filaments with dark lanes between them, not an even cream.
    float density = (0.16 + 1.5 * body * body) * (0.55 + 0.75 * smoothstep(0.3, 0.75, fine));

    float inner = smoothstep(diskInner * 0.9, diskInner * 1.12, r);
    float outer = 1.0 - smoothstep(diskOuter * 0.4, diskOuter, r);
    float profile = pow(diskInner / r, 2.2) * inner * outer;

    float3 tangent = normalize(float3(-hit.z, 0.0, hit.x));
    float beta = min(sqrt(0.5 / r), 0.6);
    float gamma = rsqrt(1.0 - beta * beta);
    float3 toCamera = -normalize(rayDir);
    float doppler = 1.0 / (gamma * (1.0 - beta * dot(tangent, toCamera)));
    float shift = doppler * sqrt(max(1.0 - 1.0 / r, 0.02));
    float temperature = pow(diskInner / r, 0.75) * shift;

    float emission = profile * density * pow(shift, 3.0) * 2.4;
    float alpha = clamp(profile * density * 1.5 + 0.04 * inner * outer, 0.0, 0.94);
    return float4(heat(temperature) * emission, alpha);
}

/// One frame's uniforms, laid out to match `FieldUniforms` in Swift.
struct FieldUniforms {
    float3 cameraPosition;
    float3 forward;
    float3 right;
    float3 up;
    float2 size;
    float2 principal;
    float time;
    float focal;
    float light;
    float pixelsPerPoint;
};

// The lensing map. A Schwarzschild hole is spherically symmetric, so a photon
// leaving the camera stays in one plane and its whole path depends on a single
// number: the angle alpha between its direction and the hole. Each frame one
// thread per alpha traces that path once and writes r(phi), the photon's
// distance from the hole at each angle phi around it, plus where it ends.
// Every pixel then reads its photon's path instead of tracing it.
constant int lensRows = 2048;      // alpha samples, denser near the hole
constant int lensColumns = 1024;   // phi samples over two full orbits
constant float lensSweep = 4.0 * M_PI_F;
constant float escapedRadius = 10000.0;

/// Row coordinate for an angle off the hole's direction: alpha = pi u^2.
static float lensRow(float alpha) { return sqrt(max(alpha, 0.0) / M_PI_F); }

/// Traces one photon in its plane: the camera at (r0, 0), the photon leaving at
/// angle alpha off the inward direction, turning toward +y.
kernel void traceLensing(texture2d<float, access::write> radii [[texture(0)]],
                         texture2d<float, access::write> ends [[texture(1)]],
                         constant FieldUniforms &u [[buffer(0)]],
                         uint row [[thread_position_in_grid]]) {
    if (row >= uint(lensRows)) { return; }
    float r0 = length(u.cameraPosition);
    float unit = float(row) / float(lensRows - 1);
    float alpha = M_PI_F * unit * unit;
    float2 p = float2(r0, 0.0);
    float2 v = float2(-cos(alpha), sin(alpha));
    float h = r0 * sin(alpha);
    float h2 = h * h;

    float step = lensSweep / float(lensColumns - 1);
    int column = 0;
    float phi = 0.0;
    float lastR = r0;
    float lastPhi = 0.0;
    float closest = r0;
    float escaped = 0.0;
    float2 heading = float2(0.0);

    if (r0 < 1.0) {
        for (; column < lensColumns; column++) { radii.write(float4(0.0), uint2(column, row)); }
        ends.write(float4(0.0, 0.0, 0.0, r0), uint2(row, 0));
        return;
    }
    radii.write(float4(r0), uint2(0, row));
    column = 1;

    for (int i = 0; i < 6000 && column < lensColumns; i++) {
        float r2 = dot(p, p);
        float r = sqrt(r2);
        if (r < 1.0) { break; }
        if (dot(p, v) > 0.0 && r > max(r0 * 1.2, 60.0)) {
            // Out of reach of anything: finish the weak-field bend analytically.
            float2 dir = normalize(v);
            float along = dot(p, dir);
            float2 offAxis = p - dir * along;
            float b = max(length(offAxis), 0.001);
            float2 final = dir - (1.0 - along / r) / b * offAxis / b;
            heading = normalize(final);
            escaped = 1.0;
            break;
        }
        float dt = clamp(0.012 * r + 0.002 * r2, 0.004, 2.0);
        float2 a = -1.5 * h2 * p / (r2 * r2 * r);
        float2 next = p + v * dt + 0.5 * a * dt * dt;
        float n2 = dot(next, next);
        float2 aNext = -1.5 * h2 * next / (n2 * n2 * sqrt(n2));
        v = v + 0.5 * (a + aNext) * dt;
        // phi only grows, so unwrap it step by step.
        float turn = atan2(next.y, next.x) - atan2(p.y, p.x);
        turn -= 2.0 * M_PI_F * floor((turn + M_PI_F) / (2.0 * M_PI_F));
        p = next;
        lastPhi = phi;
        phi += turn;
        float nr = sqrt(n2);
        closest = min(closest, nr);
        while (column < lensColumns && float(column) * step <= phi) {
            float f = (float(column) * step - lastPhi) / max(phi - lastPhi, 1e-6);
            radii.write(float4(mix(lastR, nr, f)), uint2(column, row));
            column++;
        }
        lastR = nr;
    }
    // Past the end of the path: far away if it escaped, nothing if it fell in.
    for (; column < lensColumns; column++) {
        radii.write(float4(escaped > 0.5 ? escapedRadius : 0.0), uint2(column, row));
    }
    // The escaped photon's final direction in its plane (e1, e2), whether it escaped, and how close it came.
    ends.write(float4(heading, escaped, closest), uint2(row, 0));
}

/// The stage's field at one point of the window, read from the lensing map.
static float3 blackHoleField(float2 position, constant FieldUniforms &u,
                             texture2d<float> radii, texture2d<float> ends,
                             texturecube<float> baked, texture2d<float> pattern) {
    constexpr sampler linear(filter::linear, address::clamp_to_edge);
    float2 size = u.size;
    float time = u.time;
    float light = u.light;
    float2 uv = position - u.principal;
    float3 dir = normalize(u.forward * u.focal + u.right * uv.x - u.up * uv.y);

    // The photon's plane: e1 points from the hole to the camera, e2 is the way it turns.
    float r0 = length(u.cameraPosition);
    float3 e1 = u.cameraPosition / max(r0, 1e-4);
    float cosAlpha = clamp(dot(dir, -e1), -1.0, 1.0);
    float alpha = acos(cosAlpha);
    float3 side = dir + cosAlpha * e1;
    float3 e2 = length(side) > 1e-5 ? normalize(side) : normalize(cross(e1, float3(0.0, 0.0, 1.0)));

    float rowCoord = lensRow(alpha);
    float y = (rowCoord * float(lensRows - 1) + 0.5) / float(lensRows);
    float phiScale = float(lensColumns - 1) / lensSweep;

    // Where the path can cross the disk plane: cos(phi) e1.y + sin(phi) e2.y = 0.
    float firstCrossing = atan2(-e1.y, e2.y);
    if (firstCrossing < 0.0) { firstCrossing += M_PI_F; }

    float3 col = float3(0.0);
    float transmit = 1.0;
    for (int k = 0; k < 4; k++) {
        float phi = firstCrossing + float(k) * M_PI_F;
        if (phi > lensSweep) { break; }
        float x = (phi * phiScale + 0.5) / float(lensColumns);
        float r = radii.sample(linear, float2(x, y)).r;
        if (r < diskInner * 0.9 || r > diskOuter) { continue; }
        float3 radial = cos(phi) * e1 + sin(phi) * e2;
        float3 hit = r * radial;
        hit.y = 0.0;
        // The photon's direction at the crossing, from the slope of r(phi).
        float ahead = radii.sample(linear, float2(x + 1.0 / float(lensColumns), y)).r;
        float slope = (ahead - r) * phiScale;
        float3 along = slope * radial + r * (-sin(phi) * e1 + cos(phi) * e2);
        float4 d = disk(hit, along, time, pattern);
        col += transmit * d.rgb * light;
        transmit *= 1.0 - d.a;
        if (transmit < 0.02) { break; }
    }

    // Blend the two nearest rows' endings, so the shadow's edge is smooth.
    float rowF = rowCoord * float(lensRows - 1);
    int rowA = int(floor(rowF));
    int rowB = min(rowA + 1, lensRows - 1);
    float4 endA = ends.read(uint2(rowA, 0));
    float4 endB = ends.read(uint2(rowB, 0));
    float blend = rowF - float(rowA);
    float escaped = mix(endA.z, endB.z, blend);
    float closest = mix(endA.w, endB.w, blend);
    float2 heading = endA.xy * endA.z * (1.0 - blend) + endB.xy * endB.z * blend;
    heading = length(heading) > 1e-5 ? normalize(heading) : float2(1.0, 0.0);
    float3 away = heading.x * e1 + heading.y * e2;
    // Tangential magnification: how much the lens stretches the sky around the hole here.
    float source = acos(clamp(dot(away, -e1), -1.0, 1.0));
    float stretch = sin(alpha) / max(sin(source), 1e-3);
    float stars = pow(1.0 / max(stretch, 1.0), 0.8);
    col += transmit * escaped * sky(away, baked, stars);

    // A warm glow from light grazing the photon sphere; none comes up out of the horizon.
    col += float3(1.0, 0.60, 0.26) * exp(-max(closest - 1.5, 0.0) * 6.0) * 0.12 * light * escaped;

    return col;
}

struct FieldVertex {
    float4 position [[position]];
};

/// One triangle that covers the whole target.
vertex FieldVertex fieldVertex(uint id [[vertex_id]]) {
    float2 corner = float2((id << 1) & 2, id & 2);
    FieldVertex out;
    out.position = float4(corner * 2.0 - 1.0, 0.0, 1.0);
    return out;
}

fragment half4 fieldFragment(FieldVertex in [[stage_in]], constant FieldUniforms &u [[buffer(0)]],
                             texture2d<float> radii [[texture(0)]], texture2d<float> ends [[texture(1)]],
                             texturecube<float> baked [[texture(2)]], texture2d<float> pattern [[texture(3)]]) {
    float2 position = in.position.xy / u.pixelsPerPoint;
    return half4(half3(min(blackHoleField(position, u, radii, ends, baked, pattern), float3(64.0))), 1.0h);
}

/// The camera: the HDR field plus its bloom at two scales, a filmic curve,
/// display encoding, a lens vignette and steady grain so the dark never bands.
fragment half4 composeFragment(FieldVertex in [[stage_in]], constant FieldUniforms &u [[buffer(0)]],
                               texture2d<float> field [[texture(0)]],
                               texture2d<float> near [[texture(1)]], texture2d<float> wide [[texture(2)]]) {
    constexpr sampler linear(filter::linear, address::clamp_to_edge);
    float2 pixel = in.position.xy;
    float2 uv = pixel / float2(field.get_width(), field.get_height());
    float3 col = field.read(uint2(pixel)).rgb;
    float3 glow = near.sample(linear, uv).rgb * 0.55 + wide.sample(linear, uv).rgb * 0.45;
    col = mix(col, glow, 0.12) + glow * 0.06;

    col = (col * (2.51 * col + 0.03)) / (col * (2.43 * col + 0.59) + 0.14);
    col = pow(saturate(col), float3(1.0 / 2.2));
    float2 position = pixel / u.pixelsPerPoint;
    float2 centred = (position - u.size * 0.5) / max(u.size.y, 1.0);
    col *= 1.0 - 0.32 * pow(saturate(length(centred) * 0.95), 2.4);
    col += (hash31(float3(position, 7.0)) - 0.5) / 255.0 * 1.2;
    return half4(half3(saturate(col)), 1.0h);
}
