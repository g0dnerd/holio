#version 460 core

in vec2 fragCoord;
out vec4 fragColor;

uniform float time;
uniform vec2 resolution;

// Constants
const float PI = 3.14159265359;
const float SCHWARZSCHILD_RADIUS = 0.15;
const float PHOTON_SPHERE = SCHWARZSCHILD_RADIUS * 1.5;
const float ACCRETION_INNER = SCHWARZSCHILD_RADIUS * 3.0;
const float ACCRETION_OUTER = SCHWARZSCHILD_RADIUS * 8.0;

// Pseudo-random function
float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

// Star field
vec3 starField(vec2 uv) {
    vec2 id = floor(uv * 50.0);
    vec2 gv = fract(uv * 50.0) - 0.5;

    float n = hash(id);
    float size = fract(n * 345.32) * 0.04 + 0.01;
    float brightness = fract(n * 213.4) * 0.8 + 0.2;

    // Twinkle effect
    brightness *= 0.8 + 0.2 * sin(time * 3.0 + n * 100.0);

    float star = smoothstep(size, size * 0.5, length(gv));

    vec3 col = vec3(star) * brightness;

    // Color variation
    if (n > 0.8) col *= vec3(1.2, 1.0, 0.8); // yellow
    else if (n > 0.6) col *= vec3(0.8, 0.9, 1.2); // blue
    else if (n > 0.4) col *= vec3(1.1, 0.9, 1.0); // red

    return col;
}

// Gravitational lensing
vec2 gravitationalLens(vec2 uv, vec2 blackHolePos, float mass) {
    vec2 delta = uv - blackHolePos;
    float dist = length(delta);

    // Einstein ring radius approximation
    float einsteinRadius = sqrt(2.0 * mass * SCHWARZSCHILD_RADIUS / dist);

    // Deflection angle
    float deflection = 4.0 * mass / max(dist, SCHWARZSCHILD_RADIUS);

    // Apply lensing
    vec2 lensed = uv - deflection * normalize(delta) / dist;

    return lensed;
}

// Accretion disk
vec3 accretionDisk(vec2 uv, float dist, float angle) {
    if (dist < ACCRETION_INNER || dist > ACCRETION_OUTER) return vec3(0.0);

    // Disk profile
    float diskIntensity = smoothstep(ACCRETION_OUTER, ACCRETION_OUTER - 0.1, dist) *
                         smoothstep(ACCRETION_INNER - 0.05, ACCRETION_INNER, dist);

    // Temperature gradient (hotter closer to black hole)
    float temp = 1.0 - (dist - ACCRETION_INNER) / (ACCRETION_OUTER - ACCRETION_INNER);
    temp = pow(temp, 2.0);

    // Doppler shift and beaming
    float velocity = 1.0 / sqrt(dist);
    float doppler = 1.0 + 0.3 * velocity * sin(angle - time * velocity * 2.0);

    // Spiral structure
    float spiral = sin(angle * 6.0 - dist * 15.0 + time * 2.0) * 0.1 + 0.9;

    // Hot spots
    float hotSpots = 0.0;
    for (int i = 0; i < 3; i++) {
        float spotAngle = float(i) * 2.0 * PI / 3.0 + time * 0.5;
        float spotDist = ACCRETION_INNER + (ACCRETION_OUTER - ACCRETION_INNER) * 0.5;
        vec2 spotPos = vec2(cos(spotAngle), sin(spotAngle)) * spotDist;
        float spotIntensity = exp(-length(uv - spotPos) * 8.0);
        hotSpots += spotIntensity;
    }

    diskIntensity *= spiral * doppler * (1.0 + hotSpots * 0.5);

    // Color based on temperature
    vec3 color = vec3(0.0);
    if (temp > 0.8) {
        // Very hot - blue/white
        color = mix(vec3(0.5, 0.7, 1.0), vec3(1.0, 1.0, 1.0), (temp - 0.8) * 5.0);
    } else if (temp > 0.5) {
        // Hot - yellow/orange
        color = mix(vec3(1.0, 0.5, 0.0), vec3(1.0, 0.9, 0.5), (temp - 0.5) * 3.33);
    } else {
        // Warm - red/orange
        color = mix(vec3(0.3, 0.0, 0.0), vec3(1.0, 0.5, 0.0), temp * 2.0);
    }

    return color * diskIntensity * 2.0;
}

// Relativistic jets
vec3 relativisticJets(vec2 uv, float dist) {
    // Jet cone parameters
    float jetWidth = 0.1 + dist * 0.05;
    float jetIntensity = 0.0;

    // Upper jet
    if (uv.y > 0.0) {
        float jetDist = abs(uv.x);
        jetIntensity = smoothstep(jetWidth, 0.0, jetDist) * 
                      smoothstep(2.0, 0.2, uv.y) *
                      (0.5 + 0.5 * sin(uv.y * 10.0 - time * 5.0));
    }
    // Lower jet
    else if (uv.y < 0.0) {
        float jetDist = abs(uv.x);
        jetIntensity = smoothstep(jetWidth, 0.0, jetDist) * 
                      smoothstep(2.0, 0.2, -uv.y) *
                      (0.5 + 0.5 * sin(-uv.y * 10.0 - time * 5.0));
    }

    vec3 jetColor = vec3(0.3, 0.5, 1.0) * jetIntensity * 0.3;
    return jetColor;
}

void main() {
    vec2 uv = fragCoord * 0.5 + 0.5;
    uv = (uv * 2.0 - 1.0) * vec2(resolution.x / resolution.y, 1.0);

    // Distance and angle from center
    float dist = length(uv);
    float angle = atan(uv.y, uv.x);

    // Apply gravitational lensing to background coordinates
    vec2 lensedUV = gravitationalLens(uv, vec2(0.0), 1.0);

    // Background stars (affected by lensing)
    vec3 stars = starField(lensedUV * 2.0);

    // Accretion disk (before black hole to show occlusion)
    vec3 disk = accretionDisk(uv, dist, angle);

    // Event horizon with sharp edge
    float eventHorizon = step(SCHWARZSCHILD_RADIUS, dist);

    // Photon sphere glow
    float photonGlow = exp(-abs(dist - PHOTON_SPHERE) * 30.0) * 0.5;
    vec3 photonColor = vec3(1.0, 0.8, 0.5) * photonGlow;

    // Gravitational redshift effect near event horizon
    float redshift = smoothstep(SCHWARZSCHILD_RADIUS, SCHWARZSCHILD_RADIUS * 2.0, dist);

    // Jets (only visible outside event horizon)
    vec3 jets = relativisticJets(uv, dist) * eventHorizon;

    // Combine all elements
    vec3 color = stars * 0.5;  // Dimmed background
    color += disk;
    color += photonColor;
    color += jets;

    // Apply event horizon (complete black)
    color *= eventHorizon;

    // Add subtle glow around black hole
    float glowRadius = SCHWARZSCHILD_RADIUS * 1.5;
    float glow = exp(-max(0.0, dist - glowRadius) * 3.0) * 0.2;
    color += vec3(0.5, 0.3, 0.8) * glow * eventHorizon;

    // Vignette effect
    float vignette = 1.0 - length(uv) * 0.3;
    color *= vignette;

    // Tone mapping and gamma correction
    color = color / (1.0 + color); // Reinhard tone mapping
    color = pow(color, vec3(1.0/2.2)); // Gamma correction

    fragColor = vec4(color, 1.0);
}
