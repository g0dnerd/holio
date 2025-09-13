#version 460 core

in vec2 fragCoord;
out vec4 fragColor;

uniform float time;
uniform vec2 resolution;

void main() {
    vec2 uv = fragCoord * 0.5 + 0.5;
    uv = (uv * 2.0 - 1.0) * vec2(resolution.x / resolution.y, 1.0);

    // Distance from center
    float dist = length(uv);

    // Simple black hole visualization
    float blackHoleRadius = 0.3;
    float eventHorizon = smoothstep(blackHoleRadius - 0.05, blackHoleRadius, dist);

    // Background 
    vec3 bgColor = vec3(0.1, 0.1, 0.2);

    vec3 color = mix(vec3(0.0), bgColor, eventHorizon);

    fragColor = vec4(color, 1.0);
}
