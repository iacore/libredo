const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const opt_test_filter = b.option([]const u8, "test-filter", "test filter");

    const mod = b.addModule("signals", .{
        .source_file = .{ .path = "src/main.zig" },
    });

    const tests = b.addTest(.{
        .root_source_file = .{ .path = "src/tests.zig" },
        .target = target,
        .optimize = optimize,
    });
    tests.addModule("signals", mod);
    tests.linkLibC();
    tests.addLibraryPath(.{ .path = "/usr/lib/coz-profiler" });
    tests.linkSystemLibrary("coz");
    tests.addCSourceFiles(&.{"src/coz.c"}, &.{});

    if (opt_test_filter) |x| tests.filter = x;

    b.installArtifact(tests);

    const run_tests = b.addRunArtifact(tests);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_tests.step);
}
