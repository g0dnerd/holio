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
uniform int qualityLevel;

// Constants
const float PI = 3.14159265359;
const float RS = 0.3;  // Schwarzschild radius - smaller for better view
const float DISK_INNER = 3.0 * RS;
const float DISK_OUTER = 15.0 * RS;

// Simple hash for randomness
float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

// Simple star field
vec3 starField(vec2 uv) {
    vec2 id = floor(uv * 100.0);
    vec2 gv = fract(uv * 100.0) - 0.5;

    float n = hash(id);
    float size = fract(n * 345.32) * 0.02 + 0.005;
    float brightness = fract(n * 213.4) * 0.6 + 0.4;
    brightness *= 0.8 + 0.2 * sin(time * 3.0 + n * 100.0);

    float star = smoothstep(size, size * 0.5, length(gv));

    vec3 col = vec3(star) * brightness;

    // Color variation
    if (n > 0.8) col *= vec3(1.2, 1.0, 0.8);
    else if (n > 0.6) col *= vec3(0.8, 0.9, 1.2);
    else if (n > 0.4) col *= vec3(1.1, 0.9, 1.0);

    return col * 0.5;
}

// Simple gravitational lensing approximation
vec2 gravitationalLens(vec2 uv, float mass) {
    float dist = length(uv);
    float deflection = mass * RS / max(dist, RS);
    deflection = min(deflection, 1.0);  // Prevent extreme distortion
    return uv - normalize(uv) * deflection * 0.3;
}

// Accretion disk color based on temperature
vec3 diskColor(float r) {
    float temp = pow(DISK_INNER / r, 0.75);
    temp *= diskInnerTemp;

    vec3 color;
    if (temp > 0.8) {
        color = mix(vec3(1.0, 0.8, 0.4), vec3(0.8, 0.9, 1.0), (temp - 0.8) * 5.0);
    } else if (temp > 0.4) {
        color = mix(vec3(1.0, 0.3, 0.0), vec3(1.0, 0.8, 0.4), (temp - 0.4) * 2.5);
    } else {
        color = vec3(0.8, 0.2, 0.0) * (temp * 2.5);
    }

    return color * temp;
}

void main() {
    vec2 uv = fragCoord * 0.5 + 0.5;
    uv = (uv * 2.0 - 1.0) * vec2(resolution.x / resolution.y, 1.0);

    // Distance from center
    float dist = length(uv);

    // Start with black background
    vec3 color = vec3(0.0);

    // Add background stars with lensing
    vec2 lensedUV = gravitationalLens(uv * 2.0, blackHoleMass);
    color += starField(lensedUV);

    // Event horizon - pure black
    if (dist < RS * blackHoleMass) {
        color = vec3(0.0);
    }
    else {
        // Accretion disk (thin disk approximation)
        float diskRadius = length(uv.xy);
        float diskHeight = abs(uv.y * 3.0);

        if (diskRadius > DISK_INNER && diskRadius < DISK_OUTER && diskHeight < 0.2) {
            // Basic disk physics
            float angle = atan(uv.y, uv.x);
            float velocity = sqrt(RS * blackHoleMass / diskRadius);

            // Doppler effect (simplified)
            float doppler = 1.0 + 0.4 * velocity * sin(angle - time * velocity * 2.0);

            // Spiral structure
            float spiral = 0.8 + 0.2 * sin(angle * 2.0 - log(diskRadius + 0.1) * 4.0 + time);

            // Temperature-based color
            vec3 dColor = diskColor(diskRadius);

            // Height falloff
            float heightFalloff = exp(-diskHeight * diskHeight * 50.0);

            // Add to final color
            color += dColor * doppler * spiral * heightFalloff * diskBrightness;
        }

        // Photon sphere glow
        float photonDist = abs(dist - 1.5 * RS * blackHoleMass);
        float photonGlow = exp(-photonDist * 20.0) * 0.3;
        color += vec3(1.0, 0.8, 0.5) * photonGlow;

        // Simple jets
        float jetWidth = 0.05 + abs(uv.y) * 0.02;
        if (abs(uv.x) < jetWidth && abs(uv.y) > RS * blackHoleMass && abs(uv.y) < 2.0) {
            float jetIntensity = exp(-abs(uv.x) / jetWidth * 3.0);
            jetIntensity *= (1.0 - abs(uv.y) / 2.0);
            jetIntensity *= 0.5 + 0.5 * sin(uv.y * 10.0 - time * 5.0);
            color += vec3(0.4, 0.6, 1.0) * jetIntensity * 0.5;
        }
    }

    // Edge darkening around event horizon
    float edgeDist = dist - RS * blackHoleMass;
    if (edgeDist > 0.0 && edgeDist < 0.2) {
        float darkness = 1.0 - exp(-edgeDist * 10.0);
        color *= darkness;
    }

    // Subtle vignette
    color *= 1.0 - length(uv) * 0.15;

    // Tone mapping
    color = color / (1.0 + color);

    // Gamma correction
    color = pow(color, vec3(1.0 / 2.2));

    fragColor = vec4(color, 1.0);
}
