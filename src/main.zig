const std = @import("std");

const gl = @cImport({
    @cDefine("GL_GLEXT_PROTOTYPES", "1");
    @cInclude("GL/gl.h");
});
const glfw = @cImport({
    @cInclude("GLFW/glfw3.h");
});

// Define GLFW error callback
export fn glfw_error_callback(code: c_int, msg: [*c]const u8) callconv(.c) void {
    std.debug.print("glfw error (code {d}): {s}\n", .{ code, msg });
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
        std.debug.print("{s}\n", .{buf[0..@intCast(len)]});
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
        std.debug.print("{s}\n", .{buf[0..@intCast(len)]});
        return error.ProgramLinking;
    }

    return program;
}

pub fn main() !void {
    _ = glfw.glfwSetErrorCallback(glfw_error_callback);
    _ = glfw.glfwInit();
    glfw.glfwWindowHint(glfw.GLFW_CONTEXT_VERSION_MAJOR, 4);
    glfw.glfwWindowHint(glfw.GLFW_CONTEXT_VERSION_MINOR, 6);
    glfw.glfwWindowHint(glfw.GLFW_OPENGL_PROFILE, glfw.GLFW_OPENGL_CORE_PROFILE);

    const window = glfw.glfwCreateWindow(1920, 1080, "demo", null, null);

    if (window == null) {
        return error.InitWindow;
    }
    glfw.glfwMakeContextCurrent(window);

    const shader_program = try createProgram();

    // Create VAO
    var vao: c_uint = 0;
    gl.glGenVertexArrays(1, &vao);
    gl.glBindVertexArray(vao);

    // Get uniform locations
    const time_location = gl.glGetUniformLocation(shader_program, "time");
    const resolution_location = gl.glGetUniformLocation(shader_program, "resolution");

    gl.glUseProgram(shader_program);

    while (glfw.glfwWindowShouldClose(window) == glfw.GLFW_FALSE) {
        const current_time: f32 = @floatCast(glfw.glfwGetTime());

        var width: c_int = 0;
        var height: c_int = 0;
        glfw.glfwGetFramebufferSize(window, &width, &height);

        gl.glViewport(0, 0, width, height);

        gl.glClearColor(0.0, 0.0, 0.0, 1.0);
        gl.glClear(gl.GL_COLOR_BUFFER_BIT);

        // Update uniforms
        gl.glUniform1f(time_location, current_time);
        gl.glUniform2f(resolution_location, @floatFromInt(width), @floatFromInt(height));

        // Draw fullscreen triangle
        gl.glDrawArrays(gl.GL_TRIANGLES, 0, 3);

        glfw.glfwSwapBuffers(window);
        glfw.glfwPollEvents();
    }

    gl.glDeleteVertexArrays(1, &vao);
    gl.glDeleteProgram(shader_program);
    glfw.glfwTerminate();
}
