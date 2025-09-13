#version 460 core

in vec2 fragCoord;
out vec4 fragColor;

// Uniforms
uniform float time;
uniform vec2 resolution;
uniform vec3 cameraPos;
uniform float blackHoleMass;
uniform float diskBrightness;
uniform float diskInnerTemp;
uniform float diskOpacity;
uniform sampler2D deflectionLUT;  // Will be created in main.zig
uniform sampler1D blackbodyLUT;   // For temperature to color mapping
uniform int qualityLevel;         // 0=low, 1=medium, 2=high, 3=ultra
uniform float blackHoleSpin;      // 0 to 0.998 (Kerr parameter)
uniform bool showPhotonRings;
uniform bool showEinsteinRings;

// Physical Constants
const float PI = 3.14159265359;
const float TWO_PI = 6.28318530718;
const float C = 1.0;  // Speed of light in geometric units
const float G = 1.0;  // Gravitational constant in geometric units

// Schwarzschild radius (event horizon for non-spinning)
const float RS = 2.0;  // In units where M = 1

// Critical radii
const float PHOTON_SPHERE = 1.5 * RS;  // Photon sphere radius
const float ISCO = 3.0 * RS;           // Innermost stable circular orbit
const float DISK_INNER = ISCO;
const float DISK_OUTER = 20.0 * RS;

// Ray marching parameters (adjusted by quality level)
const int MAX_STEPS_ULTRA = 500;
const int MAX_STEPS_HIGH = 200;
const int MAX_STEPS_MEDIUM = 100;
const int MAX_STEPS_LOW = 50;
const float MIN_STEP = 0.001;
const float INITIAL_STEP = 0.1;

// Photon ring parameters
const int MAX_PHOTON_ORBITS = 5;
const float PHOTON_RING_WIDTH = 0.05;

// ============================================================================
// UTILITY FUNCTIONS
// ============================================================================

// Improved hash function for procedural content
float hash(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * vec3(443.8975, 397.2973, 491.1871));
    p3 += dot(p3, p3.yxz + 19.19);
    return fract((p3.x + p3.y) * p3.z);
}

// 3D noise for volumetric effects
float noise3D(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);

    float n = i.x + i.y * 57.0 + 125.0 * i.z;
    return mix(
        mix(mix(hash(vec2(n, n + 1.0)), hash(vec2(n + 1.0, n + 1.0)), f.x),
            mix(hash(vec2(n + 57.0, n + 58.0)), hash(vec2(n + 58.0, n + 58.0)), f.x), f.y),
        mix(mix(hash(vec2(n + 125.0, n + 126.0)), hash(vec2(n + 126.0, n + 126.0)), f.x),
            mix(hash(vec2(n + 182.0, n + 183.0)), hash(vec2(n + 183.0, n + 183.0)), f.x), f.y),
        f.z
    );
}

// Convert temperature to blackbody color (using Planck's law approximation)
vec3 blackbodyColor(float temp) {
    // Temperature in Kelvin (scaled from dimensionless units)
    float T = temp * 10000.0;

    vec3 color;

    if (T < 1000.0) {
        // Very cool - deep red
        color = vec3(0.3, 0.0, 0.0);
    } else if (T < 3000.0) {
        // Red to orange
        float t = (T - 1000.0) / 2000.0;
        color = mix(vec3(0.5, 0.0, 0.0), vec3(1.0, 0.5, 0.0), t);
    } else if (T < 5000.0) {
        // Orange to yellow
        float t = (T - 3000.0) / 2000.0;
        color = mix(vec3(1.0, 0.5, 0.0), vec3(1.0, 0.9, 0.3), t);
    } else if (T < 7000.0) {
        // Yellow to white
        float t = (T - 5000.0) / 2000.0;
        color = mix(vec3(1.0, 0.9, 0.3), vec3(1.0, 1.0, 0.95), t);
    } else if (T < 10000.0) {
        // White to blue-white
        float t = (T - 7000.0) / 3000.0;
        color = mix(vec3(1.0, 1.0, 0.95), vec3(0.8, 0.9, 1.0), t);
    } else {
        // Very hot - blue
        color = vec3(0.6, 0.8, 1.0);
    }

    // Add intensity scaling based on Stefan-Boltzmann law (T^4)
    float intensity = pow(T / 10000.0, 4.0);
    return color * intensity;
}

// ============================================================================
// SCHWARZSCHILD METRIC FUNCTIONS
// ============================================================================

// Schwarzschild metric coefficient
float schwarzschildF(float r) {
    return 1.0 - RS / r;
}

// Effective potential for photon orbits
float effectivePotential(float r, float L) {
    float f = schwarzschildF(r);
    return f * (1.0 + L * L / (r * r));
}

// Calculate deflection angle using improved formula
float deflectionAngle(float r, float b) {
    if (r < RS) return 0.0;  // Inside event horizon

    float ratio = RS / r;

    // Weak field approximation for large distances
    if (ratio < 0.1) {
        return 2.0 * ratio / b;
    }

    // Strong field formula near photon sphere
    float bc = sqrt(27.0) * RS;  // Critical impact parameter
    if (abs(b - bc) < 0.1) {
        // Near critical impact parameter - strong deflection
        return -PI + 2.0 * sqrt(3.0) * RS / b + 2.0 * log(abs(b / bc - 1.0) + 0.001);
    }

    // General formula
    return 4.0 * RS / b * (1.0 + ratio * ratio / 4.0);
}

// ============================================================================
// GEODESIC INTEGRATION (Verlet method for stability)
// ============================================================================

struct RayState {
    vec3 pos;
    vec3 vel;
    float properTime;
    int orbitCount;
    bool escaped;
    bool captured;
};

// Compute acceleration in Schwarzschild spacetime
vec3 computeAcceleration(vec3 pos, vec3 vel) {
    float r = length(pos);
    if (r < RS * 1.01) return vec3(0.0);  // Too close to singularity

    vec3 n = pos / r;
    float f = schwarzschildF(r);
    float dfdr = RS / (r * r);

    // Christoffel symbols contribution
    vec3 acc = -0.5 * dfdr * (dot(vel, vel) / f + f) * n;
    acc += dfdr * dot(vel, n) * vel / f;
    acc -= dot(vel, n) * dot(vel, n) * n / r;

    return acc;
}

// Integrate geodesic using Verlet method
RayState integrateGeodesic(vec3 startPos, vec3 startDir, float maxDist) {
    RayState state;
    state.pos = startPos;
    state.vel = normalize(startDir);
    state.properTime = 0.0;
    state.orbitCount = 0;
    state.escaped = false;
    state.captured = false;

    float r = length(startPos);
    float stepSize = min(INITIAL_STEP, r * 0.1);

    // Determine max steps based on quality level
    int maxSteps = qualityLevel == 3 ? MAX_STEPS_ULTRA :
                   qualityLevel == 2 ? MAX_STEPS_HIGH :
                   qualityLevel == 1 ? MAX_STEPS_MEDIUM : MAX_STEPS_LOW;

    vec3 prevPos = state.pos;
    float prevPhi = atan(state.pos.y, state.pos.x);

    for (int i = 0; i < maxSteps; i++) {
        // Adaptive step size based on distance to black hole
        r = length(state.pos);
        stepSize = mix(MIN_STEP, INITIAL_STEP, smoothstep(RS, 5.0 * RS, r));

        // Check termination conditions
        if (r < RS * 1.05) {
            state.captured = true;
            break;
        }
        if (r > maxDist || state.properTime > maxDist) {
            state.escaped = true;
            break;
        }

        // Verlet integration
        vec3 acc = computeAcceleration(state.pos, state.vel);
        vec3 newPos = state.pos + state.vel * stepSize + 0.5 * acc * stepSize * stepSize;
        vec3 newAcc = computeAcceleration(newPos, state.vel + acc * stepSize);
        vec3 newVel = state.vel + 0.5 * (acc + newAcc) * stepSize;

        // Count orbits around black hole
        float phi = atan(newPos.y, newPos.x);
        float deltaPhi = phi - prevPhi;
        if (deltaPhi > PI) deltaPhi -= TWO_PI;
        if (deltaPhi < -PI) deltaPhi += TWO_PI;
        state.orbitCount += int(abs(deltaPhi) / TWO_PI);
        prevPhi = phi;

        state.pos = newPos;
        state.vel = normalize(newVel);  // Keep unit velocity for photons
        state.properTime += stepSize;
        prevPos = state.pos;
    }

    return state;
}

// ============================================================================
// ACCRETION DISK MODEL (Novikov-Thorne thin disk)
// ============================================================================

struct DiskProperties {
    float temperature;
    float density;
    float velocity;
    vec3 color;
    float opacity;
};

// Calculate disk temperature using Novikov-Thorne model
float diskTemperature(float r) {
    if (r < DISK_INNER || r > DISK_OUTER) return 0.0;

    // Efficiency factor for accretion
    float eta = 1.0 - sqrt(1.0 - 2.0 / (3.0 * ISCO / RS));

    // Temperature profile T ∝ r^(-3/4) with inner edge correction
    float rISCO = ISCO / RS;
    float rNorm = r / RS;

    // Page-Thorne correction factor
    float correction = 1.0 - sqrt(rISCO / rNorm);

    // Base temperature scaling
    float temp = diskInnerTemp * pow(rISCO / rNorm, 0.75) * correction;

    // Add hot spots and turbulence
    float angle = atan(r * sin(time * 0.5), r * cos(time * 0.5));
    temp *= 1.0 + 0.2 * sin(angle * 3.0 - r * 2.0 + time);

    return temp;
}

// Calculate orbital velocity (Keplerian for thin disk)
float orbitalVelocity(float r) {
    if (r < ISCO) return 0.0;
    return sqrt(RS / (2.0 * r));  // v = sqrt(GM/r) in geometric units
}

// Get full disk properties at a given position
DiskProperties getDiskProperties(vec3 pos) {
    DiskProperties props;

    float r = length(pos.xy);
    float z = pos.z;

    // Disk height profile (geometrically thin)
    float h = 0.1 * r * (r / DISK_OUTER);  // h/r ~ 0.1 at outer edge

    // Vertical density profile (Gaussian)
    props.density = exp(-z * z / (2.0 * h * h));

    // Temperature and color
    props.temperature = diskTemperature(r);
    props.color = blackbodyColor(props.temperature);

    // Orbital velocity
    props.velocity = orbitalVelocity(r);

    // Opacity (higher near inner edge)
    props.opacity = diskOpacity * props.density * 
                    (1.0 + 2.0 * exp(-(r - DISK_INNER) / RS));

    // Add spiral density waves
    float spiral = sin(atan(pos.y, pos.x) * 2.0 - log(r) * 5.0 + time * 0.3);
    props.density *= 1.0 + 0.3 * spiral;
    props.opacity *= 1.0 + 0.2 * spiral;

    return props;
}

// ============================================================================
// RELATIVISTIC EFFECTS
// ============================================================================

// Calculate Doppler factor for moving material
float dopplerFactor(vec3 pos, vec3 vel, vec3 viewDir) {
    float beta = length(vel);
    float gamma = 1.0 / sqrt(1.0 - beta * beta);
    float cosTheta = dot(normalize(vel), -viewDir);
    return 1.0 / (gamma * (1.0 - beta * cosTheta));
}

// Calculate gravitational redshift
float gravitationalRedshift(float rEmit, float rObs) {
    return sqrt(schwarzschildF(rObs) / schwarzschildF(rEmit));
}

// Combined relativistic beaming and Doppler effect
float relativisticBeaming(vec3 pos, vec3 viewDir) {
    float r = length(pos.xy);
    if (r < DISK_INNER || r > DISK_OUTER) return 1.0;

    // Orbital velocity vector (counterclockwise)
    float v = orbitalVelocity(r);
    vec3 velDir = normalize(vec3(-pos.y, pos.x, 0.0));
    vec3 vel = velDir * v;

    // Doppler factor
    float D = dopplerFactor(pos, vel, viewDir);

    // Beaming: observed flux ∝ D^(3+α) where α is spectral index
    float alpha = 0.0;  // For thermal emission
    return pow(D, 3.0 + alpha);
}

// ============================================================================
// PHOTON RINGS AND EINSTEIN RINGS
// ============================================================================

// Calculate photon ring intensity for given orbit count
float photonRingIntensity(int n) {
    if (n <= 0) return 0.0;
    // Each successive ring is exponentially dimmer
    // Intensity ratio ~ e^(-2π) ≈ 0.0019
    return exp(-TWO_PI * float(n));
}

// Check if ray passes through photon sphere region
bool isInPhotonRing(vec3 pos, float tolerance) {
    float r = length(pos);
    return abs(r - PHOTON_SPHERE) < tolerance * PHOTON_RING_WIDTH;
}

// ============================================================================
// BACKGROUND STAR FIELD WITH LENSING
// ============================================================================

vec3 lensedStarField(vec3 rayDir, RayState rayState) {
    // Use final ray direction after geodesic integration
    vec3 lensedDir = rayState.escaped ? normalize(rayState.vel) : rayDir;

    // Convert to spherical coordinates for star placement
    float theta = acos(lensedDir.z);
    float phi = atan(lensedDir.y, lensedDir.x);

    // Create tiled grid for stars
    vec2 grid = vec2(theta, phi) * 20.0;
    vec2 id = floor(grid);
    vec2 gv = fract(grid) - 0.5;

    float n = hash(id);

    // Star properties
    float size = fract(n * 345.32) * 0.03 + 0.005;
    float brightness = fract(n * 213.4) * 0.7 + 0.3;

    // Twinkle effect
    brightness *= 0.9 + 0.1 * sin(time * 4.0 + n * 100.0);

    // Star shape (gaussian)
    float star = exp(-dot(gv, gv) / (size * size));

    // Color variation
    vec3 color = vec3(star * brightness);
    if (n > 0.8) color *= vec3(1.1, 1.0, 0.9);      // Yellow
    else if (n > 0.6) color *= vec3(0.9, 0.95, 1.1); // Blue
    else if (n > 0.4) color *= vec3(1.1, 0.9, 0.9);  // Red

    // Add Einstein ring for perfectly aligned background sources
    if (showEinsteinRings) {
        float ringRadius = sqrt(4.0 * RS * length(rayState.pos));
        float ringDist = abs(length(rayDir.xy) - ringRadius / length(rayState.pos));
        float ring = exp(-ringDist * ringDist * 1000.0) * 0.5;
        color += vec3(ring) * vec3(0.8, 0.9, 1.0);
    }

    // Apply magnification from lensing
    float magnification = 1.0;
    if (rayState.orbitCount > 0) {
        magnification = 1.0 + float(rayState.orbitCount) * 0.5;
    }

    return color * magnification;
}

// ============================================================================
// RELATIVISTIC JETS
// ============================================================================

vec3 relativisticJet(vec3 pos, vec3 rayDir) {
    // Jet axis along z
    float r = length(pos.xy);
    float z = abs(pos.z);

    if (z < 0.5 || z > 50.0) return vec3(0.0);

    // Jet opening angle (collimation)
    float openingAngle = 0.2 / (1.0 + z * 0.1);
    float jetRadius = z * tan(openingAngle);

    if (r > jetRadius) return vec3(0.0);

    // Jet intensity profile (Gaussian in radius)
    float intensity = exp(-r * r / (jetRadius * jetRadius * 0.5));

    // Relativistic beaming
    float jetVelocity = 0.95;  // 0.95c
    vec3 jetDir = vec3(0.0, 0.0, sign(pos.z));
    float gamma = 1.0 / sqrt(1.0 - jetVelocity * jetVelocity);
    float doppler = 1.0 / (gamma * (1.0 - jetVelocity * dot(jetDir, -rayDir)));

    // Apply beaming
    intensity *= pow(doppler, 3.0);

    // Add shock structure
    float shocks = 1.0 + 0.5 * sin(z * 2.0 - time * 3.0);
    intensity *= shocks;

    // Jet color (synchrotron blue)
    vec3 color = vec3(0.4, 0.6, 1.0) * intensity * 0.5;

    // Add knots and hot spots
    float knots = noise3D(pos * 0.5 + vec3(0.0, 0.0, time * 2.0));
    color *= 1.0 + knots * 0.5;

    return color;
}

// ============================================================================
// MAIN RENDERING FUNCTION
// ============================================================================

void main() {
    // Normalized device coordinates
    vec2 uv = fragCoord * 0.5 + 0.5;
    uv = (uv * 2.0 - 1.0) * vec2(resolution.x / resolution.y, 1.0);

    // Camera ray setup
    vec3 rayOrigin = cameraPos;
    vec3 forward = normalize(-cameraPos);
    vec3 right = normalize(cross(vec3(0.0, 0.0, 1.0), forward));
    vec3 up = cross(forward, right);
    vec3 rayDir = normalize(forward + uv.x * right + uv.y * up);

    // Integrate geodesic
    RayState rayState = integrateGeodesic(rayOrigin, rayDir, 100.0);

    // Initialize color accumulator
    vec3 color = vec3(0.0);
    float alpha = 0.0;

    // Background stars (with gravitational lensing)
    if (rayState.escaped) {
        color = lensedStarField(rayDir, rayState) * 0.5;
    }

    // Photon rings (if enabled and ray orbited)
    if (showPhotonRings && rayState.orbitCount > 0) {
        float ringIntensity = photonRingIntensity(rayState.orbitCount);
        vec3 ringColor = vec3(1.0, 0.9, 0.7) * ringIntensity;
        color += ringColor;
    }

    // Ray march through accretion disk
    if (!rayState.captured) {
        vec3 pos = rayOrigin;
        vec3 dir = rayDir;
        float totalOpacity = 0.0;
        vec3 diskColor = vec3(0.0);

        // Simple ray marching for disk intersection
        float stepSize = 0.1;
        for (int i = 0; i < 100; i++) {
            pos += dir * stepSize;

            float r = length(pos.xy);
            float z = abs(pos.z);

            // Check if in disk region
            if (r >= DISK_INNER && r <= DISK_OUTER && z < 0.5) {
                DiskProperties disk = getDiskProperties(pos);

                // Apply relativistic effects
                float beaming = relativisticBeaming(pos, dir);
                float redshift = gravitationalRedshift(r, length(rayOrigin));

                // Accumulate disk emission
                float opacity = disk.opacity * stepSize;
                diskColor += disk.color * beaming * redshift * opacity * (1.0 - totalOpacity);
                totalOpacity += opacity * (1.0 - totalOpacity);

                if (totalOpacity > 0.99) break;
            }

            // Check if ray escaped or was captured
            if (length(pos) > 50.0 || length(pos) < RS * 1.1) break;
        }

        color += diskColor * diskBrightness;
        alpha = max(alpha, totalOpacity);
    }

    // Relativistic jets
    vec3 jetColor = relativisticJet(rayState.pos, rayDir);
    color += jetColor;

    // Event horizon (complete absorption)
    if (rayState.captured) {
        color = vec3(0.0);
        alpha = 1.0;
    }

    // Add subtle glow around black hole
    float r = length(uv);
    float glow = exp(-max(0.0, r - RS * 2.0) * 2.0) * 0.1;
    color += vec3(0.5, 0.3, 0.8) * glow;

    // Vignette effect
    float vignette = 1.0 - length(uv) * 0.2;
    color *= vignette;

    // Tone mapping (ACES approximation)
    color = color / (color + 0.155) * 1.019;

    // Gamma correction
    color = pow(color, vec3(1.0 / 2.2));

    // Output
    fragColor = vec4(color, 1.0);
}
