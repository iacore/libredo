const std = @import("std");

var mod: *std.Build.Module = undefined;
fn link(exe: *std.Build.CompileStep, add_coz: bool) void {
    exe.addModule("signals", mod);

    if (add_coz) {
        exe.linkLibC();
        exe.addLibraryPath(.{ .path = "/usr/lib/coz-profiler" });
        exe.linkSystemLibrary("coz");
        exe.addCSourceFiles(&.{"src/coz.c"}, &.{});
    }
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const opt_test_filter = b.option([]const u8, "test-filter", "test filter");

    mod = b.addModule("signals", .{
        .source_file = .{ .path = "src/main.zig" },
    });

    const bench = b.addExecutable(.{
        .name = "bench",
        .root_source_file = .{ .path = "src/tests.zig" },
    });
    link(bench, true);
    b.installArtifact(bench);

    const tests = b.addTest(.{
        .root_source_file = .{ .path = "src/tests.zig" },
        .target = target,
        .optimize = optimize,
    });
    if (opt_test_filter) |x| tests.filter = x;
    link(tests, false);
    b.installArtifact(tests);

    const run_tests = b.addRunArtifact(tests);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_tests.step);
}
