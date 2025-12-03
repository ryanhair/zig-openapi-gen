const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "openapi-gen",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Generation steps for tests
    const gen_simple_cmd = b.addRunArtifact(exe);
    gen_simple_cmd.addArgs(&.{ "generate", "specs/simple.json", "src/generated/simple" });
    const gen_simple_step = b.step("gen-simple", "Generate simple client");
    gen_simple_step.dependOn(&gen_simple_cmd.step);

    const gen_advanced_cmd = b.addRunArtifact(exe);
    gen_advanced_cmd.addArgs(&.{ "generate", "specs/advanced.json", "src/generated/advanced" });
    const gen_advanced_step = b.step("gen-advanced", "Generate advanced client");
    gen_advanced_step.dependOn(&gen_advanced_cmd.step);

    const simple_mod = b.createModule(.{
        .root_source_file = b.path("src/generated/simple/root.zig"),
    });
    const advanced_mod = b.createModule(.{
        .root_source_file = b.path("src/generated/advanced/root.zig"),
    });

    const e2e_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/e2e.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    e2e_tests.step.dependOn(gen_simple_step);
    e2e_tests.step.dependOn(gen_advanced_step);

    e2e_tests.root_module.addImport("simple", simple_mod);
    e2e_tests.root_module.addImport("advanced", advanced_mod);

    const test_step = b.step("test", "Run unit tests");
    const run_e2e_tests = b.addRunArtifact(e2e_tests);
    test_step.dependOn(&run_e2e_tests.step);
}
