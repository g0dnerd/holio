const std = @import("std");

const gl = @cImport({
    @cDefine("GL_GLEXT_PROTOTYPES", "1");
    @cInclude("GL/gl.h");
});
const glfw = @cImport({
    @cInclude("GLFW/glfw3.h");
});

// Simulation parameters
var camera_distance: f32 = 5.0;
var camera_angle: f32 = 0.0;
var camera_height: f32 = 1.0;
var black_hole_mass: f32 = 1.0;
var disk_brightness: f32 = 1.5;
var disk_inner_temp: f32 = 1.0;
var disk_opacity: f32 = 0.8;
var time_scale: f32 = 1.0;
var paused: bool = false;

// Mouse state
var last_mouse_x: f64 = 0.0;
var last_mouse_y: f64 = 0.0;
var mouse_pressed: bool = false;

// GLFW error callback
export fn glfw_error_callback(code: c_int, msg: [*c]const u8) callconv(.c) void {
    std.debug.print("GLFW error (code {d}): {s}\n", .{ code, msg });
}

// Key callback for controls
export fn key_callback(window: ?*glfw.GLFWwindow, key: c_int, scancode: c_int, action: c_int, mods: c_int) callconv(.c) void {
    _ = scancode;
    _ = mods;

    if (action == glfw.GLFW_PRESS or action == glfw.GLFW_REPEAT) {
        switch (key) {
            glfw.GLFW_KEY_ESCAPE => glfw.glfwSetWindowShouldClose(window, glfw.GLFW_TRUE),
            glfw.GLFW_KEY_SPACE => paused = !paused,
            glfw.GLFW_KEY_W => camera_distance -= 0.2,
            glfw.GLFW_KEY_S => camera_distance += 0.2,
            glfw.GLFW_KEY_A => camera_angle -= 0.1,
            glfw.GLFW_KEY_D => camera_angle += 0.1,
            glfw.GLFW_KEY_Q => camera_height += 0.1,
            glfw.GLFW_KEY_E => camera_height -= 0.1,
            glfw.GLFW_KEY_UP => black_hole_mass = @min(3.0, black_hole_mass + 0.1),
            glfw.GLFW_KEY_DOWN => black_hole_mass = @max(0.1, black_hole_mass - 0.1),
            glfw.GLFW_KEY_LEFT => time_scale = @max(0.0, time_scale - 0.1),
            glfw.GLFW_KEY_RIGHT => time_scale = @min(5.0, time_scale + 0.1),
            glfw.GLFW_KEY_EQUAL => disk_brightness = @min(3.0, disk_brightness + 0.1),
            glfw.GLFW_KEY_MINUS => disk_brightness = @max(0.1, disk_brightness - 0.1),
            glfw.GLFW_KEY_PERIOD => disk_inner_temp = @min(2.0, disk_inner_temp + 0.1),
            glfw.GLFW_KEY_COMMA => disk_inner_temp = @max(0.1, disk_inner_temp - 0.1),
            glfw.GLFW_KEY_O => disk_opacity = @min(1.0, disk_opacity + 0.1),
            glfw.GLFW_KEY_L => disk_opacity = @max(0.0, disk_opacity - 0.1),
            glfw.GLFW_KEY_R => {
                // Reset to defaults
                camera_distance = 5.0;
                camera_angle = 0.0;
                camera_height = 1.0;
                black_hole_mass = 1.0;
                disk_brightness = 1.5;
                disk_inner_temp = 1.0;
                disk_opacity = 0.8;
                time_scale = 1.0;
            },
            glfw.GLFW_KEY_H, glfw.GLFW_KEY_F1 => printControls(),
            else => {},
        }

        // Clamp camera distance
        camera_distance = @max(2.0, @min(20.0, camera_distance));
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
    camera_distance = @max(2.0, @min(20.0, camera_distance));
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

fn printControls() void {
    std.debug.print("\n========== BLACK HOLE CONTROLS ==========\n", .{});
    std.debug.print("Camera:\n", .{});
    std.debug.print("  W/S         - Move closer/farther\n", .{});
    std.debug.print("  A/D         - Rotate horizontally\n", .{});
    std.debug.print("  Q/E         - Move up/down\n", .{});
    std.debug.print("  Mouse drag  - Look around\n", .{});
    std.debug.print("  Scroll      - Zoom in/out\n", .{});
    std.debug.print("\nBlack Hole:\n", .{});
    std.debug.print("  Up/Down     - Adjust black hole mass\n", .{});
    std.debug.print("\nAccretion Disk:\n", .{});
    std.debug.print("  +/-         - Adjust brightness\n", .{});
    std.debug.print("  ,/.         - Adjust temperature\n", .{});
    std.debug.print("  O/L         - Adjust opacity\n", .{});
    std.debug.print("\nSimulation:\n", .{});
    std.debug.print("  Space       - Pause/resume time\n", .{});
    std.debug.print("  Left/Right  - Adjust time speed\n", .{});
    std.debug.print("  R           - Reset all parameters\n", .{});
    std.debug.print("  H/F1        - Show this help\n", .{});
    std.debug.print("  Escape      - Exit\n", .{});
    std.debug.print("=========================================\n\n", .{});
}

pub fn main() !void {
    _ = glfw.glfwSetErrorCallback(glfw_error_callback);
    _ = glfw.glfwInit();
    glfw.glfwWindowHint(glfw.GLFW_CONTEXT_VERSION_MAJOR, 4);
    glfw.glfwWindowHint(glfw.GLFW_CONTEXT_VERSION_MINOR, 6);
    glfw.glfwWindowHint(glfw.GLFW_OPENGL_PROFILE, glfw.GLFW_OPENGL_CORE_PROFILE);
    glfw.glfwWindowHint(glfw.GLFW_SAMPLES, 4); // Enable MSAA

    const window = glfw.glfwCreateWindow(1920, 1080, "Black Hole Visualization", null, null);

    if (window == null) {
        return error.InitWindow;
    }

    glfw.glfwMakeContextCurrent(window);
    glfw.glfwSwapInterval(1); // Enable vsync

    // Set callbacks
    _ = glfw.glfwSetKeyCallback(window, key_callback);
    _ = glfw.glfwSetMouseButtonCallback(window, mouse_button_callback);
    _ = glfw.glfwSetCursorPosCallback(window, cursor_position_callback);
    _ = glfw.glfwSetScrollCallback(window, scroll_callback);

    // Print controls
    printControls();

    const shader_program = try createProgram();

    // Create VAO
    var vao: c_uint = 0;
    gl.glGenVertexArrays(1, &vao);
    gl.glBindVertexArray(vao);

    // Get uniform locations
    const time_location = gl.glGetUniformLocation(shader_program, "time");
    const resolution_location = gl.glGetUniformLocation(shader_program, "resolution");
    const camera_pos_location = gl.glGetUniformLocation(shader_program, "cameraPos");
    const black_hole_mass_location = gl.glGetUniformLocation(shader_program, "blackHoleMass");
    const disk_brightness_location = gl.glGetUniformLocation(shader_program, "diskBrightness");
    const disk_inner_temp_location = gl.glGetUniformLocation(shader_program, "diskInnerTemp");
    const disk_opacity_location = gl.glGetUniformLocation(shader_program, "diskOpacity");
    const quality_level_location = gl.glGetUniformLocation(shader_program, "qualityLevel");

    gl.glUseProgram(shader_program);

    // Enable multisampling
    gl.glEnable(gl.GL_MULTISAMPLE);

    const start_time = glfw.glfwGetTime();
    var current_time: f64 = 0.0;
    var last_frame_time = start_time;
    var frame_count: u32 = 0;
    var fps_timer = start_time;

    while (glfw.glfwWindowShouldClose(window) == glfw.GLFW_FALSE) {
        const now = glfw.glfwGetTime();
        const delta_time = now - last_frame_time;
        last_frame_time = now;

        // Update time (with pause support)
        if (!paused) {
            current_time += delta_time * time_scale;
        }

        // FPS counter
        frame_count += 1;
        if (now - fps_timer >= 1.0) {
            const fps = @as(f64, @floatFromInt(frame_count)) / (now - fps_timer);
            std.debug.print("FPS: {d:.1} | Distance: {d:.1} | Mass: {d:.2} | Time Scale: {d:.1}x\n", .{ fps, camera_distance, black_hole_mass, time_scale });
            frame_count = 0;
            fps_timer = now;
        }

        var width: c_int = 0;
        var height: c_int = 0;
        glfw.glfwGetFramebufferSize(window, &width, &height);

        gl.glViewport(0, 0, width, height);

        gl.glClearColor(0.0, 0.0, 0.0, 1.0);
        gl.glClear(gl.GL_COLOR_BUFFER_BIT);

        // Calculate camera position based on controls
        const cam_x = camera_distance * @sin(camera_angle);
        const cam_y = -camera_distance * @cos(camera_angle);
        const cam_z = camera_height;

        // Update uniforms
        gl.glUniform1f(time_location, @floatCast(current_time));
        gl.glUniform2f(resolution_location, @floatFromInt(width), @floatFromInt(height));
        if (camera_pos_location >= 0) {
            gl.glUniform3f(camera_pos_location, cam_x, cam_y, cam_z);
        }
        if (black_hole_mass_location >= 0) {
            gl.glUniform1f(black_hole_mass_location, black_hole_mass);
        }
        if (disk_brightness_location >= 0) {
            gl.glUniform1f(disk_brightness_location, disk_brightness);
        }
        if (disk_inner_temp_location >= 0) {
            gl.glUniform1f(disk_inner_temp_location, disk_inner_temp);
        }
        if (disk_opacity_location >= 0) {
            gl.glUniform1f(disk_opacity_location, disk_opacity);
        }
        if (quality_level_location >= 0) {
            gl.glUniform1i(quality_level_location, 1);
        }

        // Draw fullscreen triangle
        gl.glDrawArrays(gl.GL_TRIANGLES, 0, 3);

        glfw.glfwSwapBuffers(window);
        glfw.glfwPollEvents();
    }

    gl.glDeleteVertexArrays(1, &vao);
    gl.glDeleteProgram(shader_program);
    glfw.glfwTerminate();
}
