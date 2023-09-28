const std = @import("std");
const signals = @import("signals");

extern fn coz_begin(name: [*:0]const u8) void;
extern fn coz_end(name: [*:0]const u8) void;

test "type check" {
    std.testing.refAllDeclsRecursive(signals);
}

const mod = signals.dependency_module(u64);
const Scope = mod.Tracker;

fn get(cx: *Scope, id: u64) !void {
    // std.log.warn("get({})", .{id});
    try cx.used(id);
    if (id >= 4 and (try cx.setDirty(id, false))) {
        try cx.begin(id);
        defer cx.end();
        const base = id - id % 4 - 4;
        switch (id % 4) {
            0 => {
                try get(cx, base + 1);
            },
            1 => {
                try get(cx, base + 0);
                try get(cx, base + 2);
            },
            2 => {
                try get(cx, base + 1);
                try get(cx, base + 3);
            },
            3 => {
                try get(cx, base + 2);
            },
            else => unreachable,
        }
    }
}

/// returns ns elapsed
fn run(a: std.mem.Allocator, layer_count: usize, comptime check: bool, comptime coz: bool) !u64 {
    // var opts = Scope.InitOptions{};
    // opts.dependency_pairs_capacity *= @max(1, layer_count / 100);
    // opts.dependent_stack_capacity *= @max(1, layer_count / 100);
    // opts.dirty_set_capacity *= @max(1, @as(u32, @intCast(layer_count / 100)));
    var cx = try Scope.init(a);
    defer cx.deinit();

    const base_id = (layer_count - 1) * 4;

    const checkpoint_name = try std.fmt.allocPrintZ(a, "n={}", .{layer_count});
    defer a.free(checkpoint_name);
    if (coz) coz_begin(checkpoint_name);
    defer if (coz) coz_end(checkpoint_name);

    var timer = try std.time.Timer.start();

    // register memos (by default is dirty)
    for (4..layer_count * 4) |i| {
        try cx.register(i);
    }
    // defer {
    //     for (0..layer_count * 4) |i| {
    //         cx.unregister(i);
    //     }
    // }

    if (check) for (4..layer_count * 4) |i| {
        // cx.pairs.dumpLog();
        try std.testing.expect(cx.isDirty(i));
    };

    const ns_prepare = timer.lap();

    try get(&cx, base_id + 0);
    try get(&cx, base_id + 1);
    try get(&cx, base_id + 2);
    try get(&cx, base_id + 3);

    if (check) for (4..layer_count * 4) |i| {
        // cx.pairs.dumpLog();
        try std.testing.expect(!cx.isDirty(i));
    };

    const ns0 = timer.lap();

    try get(&cx, base_id + 0);
    try get(&cx, base_id + 1);
    try get(&cx, base_id + 2);
    try get(&cx, base_id + 3);

    if (check) for (4..layer_count * 4) |i| {
        // cx.pairs.dumpLog();
        try std.testing.expect(!cx.isDirty(i));
    };

    const ns1 = timer.lap();
    _ = ns1;

    try cx.invalidate(0);
    try cx.invalidate(1);
    try cx.invalidate(2);
    try cx.invalidate(3);

    if (check) {
        // cx.pairs.dumpLog();

        // {
        //     var it = cx.dirty_set.iterator();
        //     while (it.next()) |kv| {
        //         std.log.warn("dirty: {}", .{kv.key_ptr.*});
        //     }
        // }
        // {
        //     for (cx.pairs.items) |kv| {
        //         std.log.warn("dep: {} -> {}", .{ kv[0], kv[1] });
        //     }
        // }

        for (4..layer_count * 4) |i| {
            try std.testing.expect(cx.isDirty(i));
        }
    }

    const ns2 = timer.lap();
    _ = ns2;

    try get(&cx, base_id + 0);
    // std.log.warn("after base_id+0", .{});
    // cx.pairs.dumpLog();

    try get(&cx, base_id + 1);
    // std.log.warn("after base_id+1", .{});
    // cx.pairs.dumpLog();
    try get(&cx, base_id + 2);
    // cx.pairs.dumpLog();
    // unreachable;
    try get(&cx, base_id + 3);

    if (check) for (4..layer_count * 4) |i| {
        try std.testing.expect(!cx.isDirty(i));
    };

    const ns3 = timer.lap();
    _ = ns3;

    try get(&cx, base_id + 0);
    try get(&cx, base_id + 1);
    try get(&cx, base_id + 2);
    try get(&cx, base_id + 3);

    if (check) for (4..layer_count * 4) |i| {
        try std.testing.expect(!cx.isDirty(i));
    };

    const ns4 = timer.lap();
    _ = ns4;

    // std.log.warn("time used: {any}", .{[_]u64{ ns_prepare, ns0, ns1, ns2, ns3, ns4 }});

    // return ns_prepare + ns0 + ns1 + ns2 + ns3 + ns4;
    return ns_prepare + ns0;
}

test "sanity check" {
    _ = try run(std.testing.allocator, 2, true, false);
}

test "verify dependency" {
    var cx = try Scope.init(std.testing.allocator);
    defer cx.deinit();

    try std.testing.expectEqualDeep(@as([]const mod.Entry, &.{}), cx.pairs.arr.items);

    for (0..16) |i| try cx.register(i);

    try std.testing.expectEqualDeep(@as([]const mod.Entry, &.{}), cx.pairs.arr.items);

    for (12..16) |i| try get(&cx, i);

    const expected = [_]mod.Entry{
        .{ 4, 1 },
        .{ 5, 0 },
        .{ 5, 2 },
        .{ 6, 1 },
        .{ 6, 3 },
        .{ 7, 2 },
        .{ 8, 5 },
        .{ 9, 4 },
        .{ 9, 6 },
        .{ 10, 5 },
        .{ 10, 7 },
        .{ 11, 6 },
        .{ 12, 9 },
        .{ 13, 8 },
        .{ 13, 10 },
        .{ 14, 9 },
        .{ 14, 11 },
        .{ 15, 10 },
    };
    try std.testing.expectEqualDeep(@as([]const mod.Entry, &expected), cx.pairs.arr.items);
}

fn get2(cx: *Scope, id: u64) !void {
    try cx.used(id);
    if (try cx.setDirty(id, false)) {
        try cx.begin(id);
        defer cx.end();
        switch (id % 3) {
            0 => {
                try get2(cx, 1);
            },
            1 => {
                try get2(cx, 2);
            },
            2 => {
                try get2(cx, 3);
            },
            else => unreachable,
        }
    }
}

test "cyclic dependency graph" {
    var cx = try Scope.init(std.testing.allocator);
    defer cx.deinit();
    try std.testing.expectEqual(@as(u32, 0), cx.dirty_set.count());
    for (1..4) |i| try cx.register(i);
    try std.testing.expectEqual(@as(u32, 3), cx.dirty_set.count());
    for (1..4) |i| {
        try get2(&cx, 3);
        try get2(&cx, 2);
        try get2(&cx, 1);
        try std.testing.expectEqual(@as(u32, 0), cx.dirty_set.count());
        try cx.invalidate(i);
        try std.testing.expectEqual(@as(u32, 3), cx.dirty_set.count());
    }
}

/// benchmark
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const RUNS_PER_TIER = 150;
    const LAYER_TIERS = [_]usize{
        10,
        100,
        500,
        1000,
        2000,
    };
    // const SOLUTIONS = {
    //   10: [2, 4, -2, -3],
    //   100: [-2, -4, 2, 3],
    //   500: [-2, 1, -4, -4],
    //   1000: [-2, -4, 2, 3],
    //   2000: [-2, 1, -4, -4],
    //   // 2500: [-2, -4, 2, 3],
    // };
    const stderr = std.io.getStdErr().writer();
    for (LAYER_TIERS) |n_layers| {
        var sum: u64 = 0;
        for (0..RUNS_PER_TIER) |_| {
            sum += try run(gpa.allocator(), n_layers, false, false);
        }
        const ns: f64 = @floatFromInt(sum / RUNS_PER_TIER);
        const ms = ns / std.time.ns_per_ms;

        try stderr.print("n_layers={} avg {d}ms\n", .{ n_layers, ms });
    }
}
