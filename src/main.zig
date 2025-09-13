const std = @import("std");

const gl = @cImport({
    @cDefine("GL_GLEXT_PROTOTYPES", "1");
    @cInclude("GL/gl.h");
});
const glfw = @cImport({
    @cInclude("GLFW/glfw3.h");
});

// Simulation parameters
var camera_distance: f32 = 10.0;
var camera_angle: f32 = 0.0;
var camera_height: f32 = 2.0;
var camera_fov: f32 = 60.0;

// Black hole parameters
var black_hole_mass: f32 = 1.0;
var black_hole_spin: f32 = 0.0; // Kerr parameter (0 to 0.998)

// Accretion disk parameters
var disk_brightness: f32 = 1.0;
var disk_inner_temp: f32 = 1.0; // Temperature at ISCO
var disk_opacity: f32 = 0.8;
var disk_turbulence: f32 = 0.3;

// Rendering parameters
var quality_level: i32 = 2; // 0=low, 1=medium, 2=high, 3=ultra
var show_photon_rings: bool = true;
var show_einstein_rings: bool = true;
var show_jets: bool = true;
var show_disk: bool = true;

// Time control
var time_scale: f32 = 1.0;
var paused: bool = false;
var total_time: f32 = 0.0;

// Performance monitoring
var frame_times: [60]f32 = [_]f32{0.0} ** 60;
var frame_time_index: usize = 0;
var target_fps: f32 = 60.0;
var auto_quality: bool = true;

// Mouse state
var last_mouse_x: f64 = 0.0;
var last_mouse_y: f64 = 0.0;
var mouse_pressed: bool = false;
var mouse_sensitivity: f32 = 0.01;

// Lookup table dimensions
const DEFLECTION_LUT_SIZE = 256;
const BLACKBODY_LUT_SIZE = 1024;

// Define GLFW error callback
export fn glfw_error_callback(code: c_int, msg: [*c]const u8) callconv(.c) void {
    std.debug.print("GLFW error (code {d}): {s}\n", .{ code, msg });
}

// Key callback for controls
export fn key_callback(window: ?*glfw.GLFWwindow, key: c_int, scancode: c_int, action: c_int, mods: c_int) callconv(.c) void {
    _ = scancode;

    if (action == glfw.GLFW_PRESS or action == glfw.GLFW_REPEAT) {
        const shift = (mods & glfw.GLFW_MOD_SHIFT) != 0;
        const ctrl = (mods & glfw.GLFW_MOD_CONTROL) != 0;

        switch (key) {
            // Basic controls
            glfw.GLFW_KEY_ESCAPE => glfw.glfwSetWindowShouldClose(window, glfw.GLFW_TRUE),
            glfw.GLFW_KEY_SPACE => paused = !paused,

            // Camera movement
            glfw.GLFW_KEY_W => camera_distance -= if (shift) 1.0 else 0.2,
            glfw.GLFW_KEY_S => camera_distance += if (shift) 1.0 else 0.2,
            glfw.GLFW_KEY_A => camera_angle -= if (shift) 0.5 else 0.1,
            glfw.GLFW_KEY_D => camera_angle += if (shift) 0.5 else 0.1,
            glfw.GLFW_KEY_Q => camera_height += if (shift) 0.5 else 0.1,
            glfw.GLFW_KEY_E => camera_height -= if (shift) 0.5 else 0.1,

            // Black hole parameters
            glfw.GLFW_KEY_UP => {
                if (ctrl) {
                    black_hole_spin = @min(0.998, black_hole_spin + 0.05);
                } else {
                    black_hole_mass = @min(5.0, black_hole_mass + 0.1);
                }
            },
            glfw.GLFW_KEY_DOWN => {
                if (ctrl) {
                    black_hole_spin = @max(0.0, black_hole_spin - 0.05);
                } else {
                    black_hole_mass = @max(0.1, black_hole_mass - 0.1);
                }
            },

            // Time control
            glfw.GLFW_KEY_LEFT => time_scale = @max(0.0, time_scale - 0.1),
            glfw.GLFW_KEY_RIGHT => time_scale = @min(5.0, time_scale + 0.1),
            glfw.GLFW_KEY_T => time_scale = if (time_scale == 0.0) 1.0 else 0.0,

            // Disk parameters
            glfw.GLFW_KEY_EQUAL, glfw.GLFW_KEY_KP_ADD => {
                if (ctrl) {
                    disk_inner_temp = @min(3.0, disk_inner_temp + 0.1);
                } else {
                    disk_brightness = @min(3.0, disk_brightness + 0.1);
                }
            },
            glfw.GLFW_KEY_MINUS, glfw.GLFW_KEY_KP_SUBTRACT => {
                if (ctrl) {
                    disk_inner_temp = @max(0.1, disk_inner_temp - 0.1);
                } else {
                    disk_brightness = @max(0.0, disk_brightness - 0.1);
                }
            },

            // Quality settings
            glfw.GLFW_KEY_1 => quality_level = 0, // Low
            glfw.GLFW_KEY_2 => quality_level = 1, // Medium
            glfw.GLFW_KEY_3 => quality_level = 2, // High
            glfw.GLFW_KEY_4 => quality_level = 3, // Ultra
            glfw.GLFW_KEY_0 => auto_quality = !auto_quality,

            // Toggle features
            glfw.GLFW_KEY_P => show_photon_rings = !show_photon_rings,
            glfw.GLFW_KEY_I => show_einstein_rings = !show_einstein_rings,
            glfw.GLFW_KEY_J => show_jets = !show_jets,
            glfw.GLFW_KEY_K => show_disk = !show_disk,

            // Disk opacity
            glfw.GLFW_KEY_O => disk_opacity = @min(1.0, disk_opacity + 0.1),
            glfw.GLFW_KEY_L => disk_opacity = @max(0.0, disk_opacity - 0.1),

            // Reset
            glfw.GLFW_KEY_R => {
                if (shift) {
                    // Reset everything
                    camera_distance = 10.0;
                    camera_angle = 0.0;
                    camera_height = 2.0;
                    camera_fov = 60.0;
                    black_hole_mass = 1.0;
                    black_hole_spin = 0.0;
                    disk_brightness = 1.0;
                    disk_inner_temp = 1.0;
                    disk_opacity = 0.8;
                    time_scale = 1.0;
                    quality_level = 2;
                } else {
                    // Reset camera only
                    camera_distance = 10.0;
                    camera_angle = 0.0;
                    camera_height = 2.0;
                }
            },

            // Help
            glfw.GLFW_KEY_H, glfw.GLFW_KEY_F1 => printControls(),

            // Screenshot info
            glfw.GLFW_KEY_F12 => printStatus(),

            else => {},
        }

        // Clamp values
        camera_distance = @max(3.0, @min(50.0, camera_distance));
        camera_height = @max(-10.0, @min(10.0, camera_height));
        camera_fov = @max(10.0, @min(120.0, camera_fov));
    }
}

// Mouse button callback
export fn mouse_button_callback(window: ?*glfw.GLFWwindow, button: c_int, action: c_int, mods: c_int) callconv(.c) void {
    _ = mods;

    if (button == glfw.GLFW_MOUSE_BUTTON_LEFT) {
        mouse_pressed = action == glfw.GLFW_PRESS;
        if (mouse_pressed) {
            glfw.glfwGetCursorPos(window, &last_mouse_x, &last_mouse_y);
        }
    }
}

// Mouse movement callback
export fn cursor_position_callback(window: ?*glfw.GLFWwindow, xpos: f64, ypos: f64) callconv(.c) void {
    _ = window;

    if (mouse_pressed) {
        const dx = xpos - last_mouse_x;
        const dy = ypos - last_mouse_y;

        camera_angle += @floatCast(dx * 0.01);
        camera_height += @floatCast(dy * 0.01);

        camera_height = @max(-3.0, @min(3.0, camera_height));

        last_mouse_x = xpos;
        last_mouse_y = ypos;
    }
}

// Scroll callback for zoom
export fn scroll_callback(window: ?*glfw.GLFWwindow, xoffset: f64, yoffset: f64) callconv(.c) void {
    _ = window;
    _ = xoffset;

    camera_distance -= @floatCast(yoffset * 0.5);
    camera_distance = @max(3.0, @min(50.0, camera_distance));
}

fn compileShader(src: [:0]const u8, shader_type: gl.GLuint) !gl.GLuint {
    const shader = gl.glCreateShader(shader_type);
    const len_int: c_int = @intCast(src.len);
    gl.glShaderSource(shader, 1, &src.ptr, &len_int);
    gl.glCompileShader(shader);

    var success: gl.GLint = 0;
    var buf: [4096]u8 = undefined;
    gl.glGetShaderiv(shader, gl.GL_COMPILE_STATUS, &success);

    if (success == 0) {
        var len: gl.GLsizei = 0;
        gl.glGetShaderInfoLog(shader, buf.len, &len, &buf);
        std.debug.print("Shader compilation error:\n{s}\n", .{buf[0..@intCast(len)]});
        return error.ShaderCompilation;
    }

    return shader;
}

fn createProgram() !gl.GLuint {
    const vert = try compileShader(@embedFile("vs.glsl"), gl.GL_VERTEX_SHADER);
    defer gl.glDeleteShader(vert);
    const frag = try compileShader(@embedFile("fs.glsl"), gl.GL_FRAGMENT_SHADER);
    defer gl.glDeleteShader(frag);

    const program = gl.glCreateProgram();
    gl.glAttachShader(program, vert);
    gl.glAttachShader(program, frag);
    gl.glLinkProgram(program);

    var success: gl.GLint = 0;
    var buf: [4096]u8 = undefined;
    gl.glGetProgramiv(program, gl.GL_LINK_STATUS, &success);

    if (success == 0) {
        var len: gl.GLsizei = 0;
        gl.glGetProgramInfoLog(program, buf.len, &len, &buf);
        std.debug.print("Program linking error:\n{s}\n", .{buf[0..@intCast(len)]});
        return error.ProgramLinking;
    }

    return program;
}

// Create deflection lookup table
fn createDeflectionLUT() gl.GLuint {
    var texture: gl.GLuint = 0;
    gl.glGenTextures(1, &texture);
    gl.glBindTexture(gl.GL_TEXTURE_2D, texture);

    // Generate deflection angle data
    var data: [DEFLECTION_LUT_SIZE][DEFLECTION_LUT_SIZE]f32 = undefined;

    for (0..DEFLECTION_LUT_SIZE) |i| {
        for (0..DEFLECTION_LUT_SIZE) |j| {
            const r = @as(f32, @floatFromInt(i)) / @as(f32, DEFLECTION_LUT_SIZE - 1) * 50.0 + 2.0;
            const b = @as(f32, @floatFromInt(j)) / @as(f32, DEFLECTION_LUT_SIZE - 1) * 10.0 + 0.1;

            // Calculate deflection angle
            const rs = 2.0; // Schwarzschild radius
            const ratio = rs / r;

            var angle: f32 = 0.0;
            if (ratio < 0.1) {
                angle = 2.0 * ratio / b;
            } else {
                const bc = @sqrt(27.0) * rs;
                if (@abs(b - bc) < 0.1) {
                    angle = -std.math.pi + 2.0 * @sqrt(3.0) * rs / b + 2.0 * @log(@abs(b / bc - 1.0) + 0.001);
                } else {
                    angle = 4.0 * rs / b * (1.0 + ratio * ratio / 4.0);
                }
            }

            data[i][j] = angle;
        }
    }

    gl.glTexImage2D(gl.GL_TEXTURE_2D, 0, gl.GL_R32F, DEFLECTION_LUT_SIZE, DEFLECTION_LUT_SIZE, 0, gl.GL_RED, gl.GL_FLOAT, &data);

    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, gl.GL_LINEAR);
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, gl.GL_LINEAR);
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_S, gl.GL_CLAMP_TO_EDGE);
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_T, gl.GL_CLAMP_TO_EDGE);

    return texture;
}

// Create blackbody color lookup table
fn createBlackbodyLUT() gl.GLuint {
    var texture: gl.GLuint = 0;
    gl.glGenTextures(1, &texture);
    gl.glBindTexture(gl.GL_TEXTURE_1D, texture);

    // Generate blackbody color data
    var data: [BLACKBODY_LUT_SIZE][3]f32 = undefined;

    for (0..BLACKBODY_LUT_SIZE) |i| {
        const t = @as(f32, @floatFromInt(i)) / @as(f32, BLACKBODY_LUT_SIZE - 1);
        const temp = t * 20000.0; // Temperature range 0-20000K

        // Simple blackbody color approximation
        var r: f32 = 0.0;
        var g: f32 = 0.0;
        var b: f32 = 0.0;

        if (temp < 1000.0) {
            r = 0.3;
            g = 0.0;
            b = 0.0;
        } else if (temp < 3000.0) {
            const tt = (temp - 1000.0) / 2000.0;
            r = 0.5 + 0.5 * tt;
            g = 0.5 * tt;
            b = 0.0;
        } else if (temp < 5000.0) {
            const tt = (temp - 3000.0) / 2000.0;
            r = 1.0;
            g = 0.5 + 0.4 * tt;
            b = 0.3 * tt;
        } else if (temp < 7000.0) {
            const tt = (temp - 5000.0) / 2000.0;
            r = 1.0;
            g = 0.9 + 0.1 * tt;
            b = 0.3 + 0.65 * tt;
        } else {
            const tt = @min(1.0, (temp - 7000.0) / 3000.0);
            r = 1.0 - 0.2 * tt;
            g = 1.0 - 0.1 * tt;
            b = 0.95 + 0.05 * tt;
        }

        // Apply intensity scaling (Stefan-Boltzmann)
        const intensity = std.math.pow(f32, temp / 10000.0, 4.0);

        data[i][0] = r * intensity;
        data[i][1] = g * intensity;
        data[i][2] = b * intensity;
    }

    gl.glTexImage1D(gl.GL_TEXTURE_1D, 0, gl.GL_RGB32F, BLACKBODY_LUT_SIZE, 0, gl.GL_RGB, gl.GL_FLOAT, &data);

    gl.glTexParameteri(gl.GL_TEXTURE_1D, gl.GL_TEXTURE_MIN_FILTER, gl.GL_LINEAR);
    gl.glTexParameteri(gl.GL_TEXTURE_1D, gl.GL_TEXTURE_MAG_FILTER, gl.GL_LINEAR);
    gl.glTexParameteri(gl.GL_TEXTURE_1D, gl.GL_TEXTURE_WRAP_S, gl.GL_CLAMP_TO_EDGE);

    return texture;
}

fn printControls() void {
    std.debug.print("\n╔════════════════════════════════════════════════════════════╗\n", .{});
    std.debug.print("║           BLACK HOLE VISUALIZATION CONTROLS               ║\n", .{});
    std.debug.print("╠════════════════════════════════════════════════════════════╣\n", .{});
    std.debug.print("║ CAMERA CONTROLS:                                          ║\n", .{});
    std.debug.print("║   W/S         - Move closer/farther (Shift: fast)        ║\n", .{});
    std.debug.print("║   A/D         - Rotate horizontally (Shift: fast)        ║\n", .{});
    std.debug.print("║   Q/E         - Move up/down (Shift: fast)               ║\n", .{});
    std.debug.print("║   Mouse drag  - Look around                              ║\n", .{});
    std.debug.print("║   Scroll      - Zoom in/out                              ║\n", .{});
    std.debug.print("║                                                           ║\n", .{});
    std.debug.print("║ BLACK HOLE PARAMETERS:                                   ║\n", .{});
    std.debug.print("║   Up/Down     - Adjust mass                              ║\n", .{});
    std.debug.print("║   Ctrl+Up/Down - Adjust spin (Kerr parameter)            ║\n", .{});
    std.debug.print("║                                                           ║\n", .{});
    std.debug.print("║ ACCRETION DISK:                                          ║\n", .{});
    std.debug.print("║   +/-         - Brightness                               ║\n", .{});
    std.debug.print("║   Ctrl +/-    - Temperature                              ║\n", .{});
    std.debug.print("║   O/L         - Opacity up/down                          ║\n", .{});
    std.debug.print("║   K           - Toggle disk visibility                   ║\n", .{});
    std.debug.print("║                                                           ║\n", .{});
    std.debug.print("║ VISUALIZATION FEATURES:                                  ║\n", .{});
    std.debug.print("║   P           - Toggle photon rings                      ║\n", .{});
    std.debug.print("║   I           - Toggle Einstein rings                    ║\n", .{});
    std.debug.print("║   J           - Toggle relativistic jets                 ║\n", .{});
    std.debug.print("║                                                           ║\n", .{});
    std.debug.print("║ QUALITY & TIME:                                          ║\n", .{});
    std.debug.print("║   1/2/3/4     - Quality (Low/Med/High/Ultra)            ║\n", .{});
    std.debug.print("║   0           - Toggle auto quality                      ║\n", .{});
    std.debug.print("║   Space       - Pause/resume                             ║\n", .{});
    std.debug.print("║   Left/Right  - Time speed                               ║\n", .{});
    std.debug.print("║   T           - Toggle time freeze                       ║\n", .{});
    std.debug.print("║                                                           ║\n", .{});
    std.debug.print("║ OTHER:                                                    ║\n", .{});
    std.debug.print("║   R           - Reset camera                             ║\n", .{});
    std.debug.print("║   Shift+R     - Reset all parameters                     ║\n", .{});
    std.debug.print("║   H/F1        - Show this help                           ║\n", .{});
    std.debug.print("║   F12         - Print status                             ║\n", .{});
    std.debug.print("║   Escape      - Exit                                     ║\n", .{});
    std.debug.print("╚════════════════════════════════════════════════════════════╝\n\n", .{});
}

// Print current status
fn printStatus() void {
    const quality_str = switch (quality_level) {
        0 => "Low",
        1 => "Medium",
        2 => "High",
        3 => "Ultra",
        else => "Unknown",
    };

    std.debug.print("\n=== BLACK HOLE STATUS ===\n", .{});
    std.debug.print("Mass: {d:.2} | Spin: {d:.3} | ", .{ black_hole_mass, black_hole_spin });
    std.debug.print("Quality: {s} | Time: {d:.1}x\n", .{ quality_str, time_scale });
    std.debug.print("Disk: Brightness={d:.1} Temp={d:.1} Opacity={d:.1}\n", .{ disk_brightness, disk_inner_temp, disk_opacity });
    std.debug.print("Features: Photon={} Einstein={} Jets={} Disk={}\n", .{ show_photon_rings, show_einstein_rings, show_jets, show_disk });
    std.debug.print("Camera: Dist={d:.1} Angle={d:.1}° Height={d:.1}\n", .{ camera_distance, camera_angle * 180.0 / std.math.pi, camera_height });
}

// Calculate average FPS
fn calculateAverageFPS() f32 {
    var sum: f32 = 0.0;
    for (frame_times) |t| {
        sum += t;
    }
    return @as(f32, frame_times.len) / sum;
}

// Auto-adjust quality based on performance
fn autoAdjustQuality(fps: f32) void {
    if (!auto_quality) return;

    if (fps < 25.0 and quality_level > 0) {
        quality_level -= 1;
        std.debug.print("Auto-adjusting quality down to: {d}\n", .{quality_level});
    } else if (fps > 55.0 and quality_level < 3) {
        quality_level += 1;
        std.debug.print("Auto-adjusting quality up to: {d}\n", .{quality_level});
    }
}

pub fn main() !void {
    // Initialize GLFW
    _ = glfw.glfwSetErrorCallback(glfw_error_callback);
    if (glfw.glfwInit() == glfw.GLFW_FALSE) {
        return error.GLFWInitFailed;
    }
    defer glfw.glfwTerminate();

    // Configure OpenGL context
    glfw.glfwWindowHint(glfw.GLFW_CONTEXT_VERSION_MAJOR, 4);
    glfw.glfwWindowHint(glfw.GLFW_CONTEXT_VERSION_MINOR, 6);
    glfw.glfwWindowHint(glfw.GLFW_OPENGL_PROFILE, glfw.GLFW_OPENGL_CORE_PROFILE);
    glfw.glfwWindowHint(glfw.GLFW_SAMPLES, 4); // MSAA

    // Create window
    const window = glfw.glfwCreateWindow(1920, 1080, "Advanced Black Hole Visualization", null, null);
    if (window == null) {
        return error.WindowCreationFailed;
    }

    glfw.glfwMakeContextCurrent(window);
    glfw.glfwSwapInterval(1); // VSync

    // Set callbacks
    _ = glfw.glfwSetKeyCallback(window, key_callback);
    _ = glfw.glfwSetMouseButtonCallback(window, mouse_button_callback);
    _ = glfw.glfwSetCursorPosCallback(window, cursor_position_callback);
    _ = glfw.glfwSetScrollCallback(window, scroll_callback);

    // Print controls on startup
    printControls();

    // Create shader program
    const shader_program = try createProgram();
    defer gl.glDeleteProgram(shader_program);

    // Create VAO for fullscreen triangle
    var vao: gl.GLuint = 0;
    gl.glGenVertexArrays(1, &vao);
    gl.glBindVertexArray(vao);
    defer gl.glDeleteVertexArrays(1, &vao);

    // Create lookup tables
    const deflection_lut = createDeflectionLUT();
    defer gl.glDeleteTextures(1, &deflection_lut);

    const blackbody_lut = createBlackbodyLUT();
    defer gl.glDeleteTextures(1, &blackbody_lut);

    // Get uniform locations
    const loc_time = gl.glGetUniformLocation(shader_program, "time");
    const loc_resolution = gl.glGetUniformLocation(shader_program, "resolution");
    const loc_camera_pos = gl.glGetUniformLocation(shader_program, "cameraPos");
    const loc_black_hole_mass = gl.glGetUniformLocation(shader_program, "blackHoleMass");
    const loc_black_hole_spin = gl.glGetUniformLocation(shader_program, "blackHoleSpin");
    const loc_disk_brightness = gl.glGetUniformLocation(shader_program, "diskBrightness");
    const loc_disk_inner_temp = gl.glGetUniformLocation(shader_program, "diskInnerTemp");
    const loc_disk_opacity = gl.glGetUniformLocation(shader_program, "diskOpacity");
    const loc_deflection_lut = gl.glGetUniformLocation(shader_program, "deflectionLUT");
    const loc_blackbody_lut = gl.glGetUniformLocation(shader_program, "blackbodyLUT");
    const loc_quality_level = gl.glGetUniformLocation(shader_program, "qualityLevel");
    const loc_show_photon_rings = gl.glGetUniformLocation(shader_program, "showPhotonRings");
    const loc_show_einstein_rings = gl.glGetUniformLocation(shader_program, "showEinsteinRings");

    // Use shader program
    gl.glUseProgram(shader_program);

    // Bind textures to texture units
    gl.glUniform1i(loc_deflection_lut, 0);
    gl.glUniform1i(loc_blackbody_lut, 1);

    // Enable multisampling
    gl.glEnable(gl.GL_MULTISAMPLE);

    // Main render loop
    const start_time = glfw.glfwGetTime();
    var last_frame_time = start_time;
    // var frame_count: u32 = 0;
    // var fps_timer = start_time;
    var quality_check_timer = start_time;

    while (glfw.glfwWindowShouldClose(window) == glfw.GLFW_FALSE) {
        const now = glfw.glfwGetTime();
        const delta_time = @as(f32, @floatCast(now - last_frame_time));
        last_frame_time = now;

        // Update time
        if (!paused) {
            total_time += delta_time * time_scale;
        }

        // Track frame times for FPS calculation
        frame_times[frame_time_index] = delta_time;
        frame_time_index = (frame_time_index + 1) % frame_times.len;

        // FPS counter and display
        // frame_count += 1;
        // if (now - fps_timer >= 1.0) {
        // const fps = calculateAverageFPS();
        // const quality_str = switch (quality_level) {
        //     0 => "LOW",
        //     1 => "MED",
        //     2 => "HIGH",
        //     3 => "ULTRA",
        //     else => "?",
        // };

        // std.debug.print("FPS: {d:.1} | Quality: {s} | Mass: {d:.2} | Spin: {d:.3} | Time: {d:.1}x\n", .{ fps, quality_str, black_hole_mass, black_hole_spin, time_scale });

        //     frame_count = 0;
        //     fps_timer = now;
        // }

        // Auto quality adjustment (check every 2 seconds)
        if (now - quality_check_timer >= 2.0) {
            const fps = calculateAverageFPS();
            autoAdjustQuality(fps);
            quality_check_timer = now;
        }

        // Get framebuffer size
        var width: c_int = 0;
        var height: c_int = 0;
        glfw.glfwGetFramebufferSize(window, &width, &height);
        gl.glViewport(0, 0, width, height);

        // Clear
        gl.glClearColor(0.0, 0.0, 0.0, 1.0);
        gl.glClear(gl.GL_COLOR_BUFFER_BIT);

        // Calculate camera position
        const cam_x = camera_distance * @sin(camera_angle) * @cos(camera_height * 0.1);
        const cam_y = camera_distance * @cos(camera_angle) * @cos(camera_height * 0.1);
        const cam_z = camera_distance * @sin(camera_height * 0.1);

        // Bind textures
        gl.glActiveTexture(gl.GL_TEXTURE0);
        gl.glBindTexture(gl.GL_TEXTURE_2D, deflection_lut);
        gl.glActiveTexture(gl.GL_TEXTURE1);
        gl.glBindTexture(gl.GL_TEXTURE_1D, blackbody_lut);

        // Update uniforms
        gl.glUniform1f(loc_time, total_time);
        gl.glUniform2f(loc_resolution, @floatFromInt(width), @floatFromInt(height));
        gl.glUniform3f(loc_camera_pos, cam_x, cam_y, cam_z);
        gl.glUniform1f(loc_black_hole_mass, black_hole_mass);
        gl.glUniform1f(loc_black_hole_spin, black_hole_spin);
        gl.glUniform1f(loc_disk_brightness, if (show_disk) disk_brightness else 0.0);
        gl.glUniform1f(loc_disk_inner_temp, disk_inner_temp);
        gl.glUniform1f(loc_disk_opacity, disk_opacity);
        gl.glUniform1i(loc_quality_level, quality_level);
        gl.glUniform1i(loc_show_photon_rings, if (show_photon_rings) 1 else 0);
        gl.glUniform1i(loc_show_einstein_rings, if (show_einstein_rings) 1 else 0);

        // Draw fullscreen triangle
        gl.glDrawArrays(gl.GL_TRIANGLES, 0, 3);

        // Swap buffers and poll events
        glfw.glfwSwapBuffers(window);
        glfw.glfwPollEvents();
    }

    std.debug.print("\nShutting down...\n", .{});
}
