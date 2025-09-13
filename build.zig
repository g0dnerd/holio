const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "holio",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    exe.linkSystemLibrary("GL");
    exe.linkSystemLibrary("glfw");
    exe.linkSystemLibrary("m");
    exe.linkLibC();

    if (optimize == .ReleaseFast or optimize == .ReleaseSmall) {
        exe.root_module.addCMacro("NDEBUG", "1");
    }

    b.installArtifact(exe);
}
