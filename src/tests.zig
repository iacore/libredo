const std = @import("std");
const signals = @import("signals");

extern fn coz_begin(name: [*:0]const u8) void;
extern fn coz_end(name: [*:0]const u8) void;

test "type check" {
    std.testing.refAllDeclsRecursive(signals);
}

const Scope = signals.DependencyTracker;

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
fn run(a: std.mem.Allocator, layer_count: usize, comptime check: bool) !u64 {
    // var opts = Scope.InitOptions{};
    // opts.dependency_pairs_capacity *= @max(1, layer_count / 100);
    // opts.dependent_stack_capacity *= @max(1, layer_count / 100);
    // opts.dirty_set_capacity *= @max(1, @as(u32, @intCast(layer_count / 100)));
    var cx = try Scope.init(a);
    defer cx.deinit();

    const base_id = (layer_count - 1) * 4;

    const checkpoint_name = try std.fmt.allocPrintZ(a, "n={}", .{layer_count});
    defer a.free(checkpoint_name);
    coz_begin(checkpoint_name);
    defer coz_end(checkpoint_name);

    var timer = try std.time.Timer.start();

    // register signals (by default is dirty)
    for (0..layer_count * 4) |i| {
        try cx.register(i);
    }
    defer {
        for (0..layer_count * 4) |i| {
            cx.unregister(i);
        }
    }

    const ns_prepare = timer.lap();

    try get(&cx, base_id + 0);
    try get(&cx, base_id + 1);
    try get(&cx, base_id + 2);
    try get(&cx, base_id + 3);

    if (check) for (4..layer_count * 4) |i| {
        try std.testing.expect(!cx.isDirty(i));
    };

    const ns0 = timer.lap();

    try get(&cx, base_id + 0);
    try get(&cx, base_id + 1);
    try get(&cx, base_id + 2);
    try get(&cx, base_id + 3);

    if (check) for (4..layer_count * 4) |i| {
        try std.testing.expect(!cx.isDirty(i));
    };

    const ns1 = timer.lap();

    try cx.invalidate(0);
    try cx.invalidate(1);
    try cx.invalidate(2);
    try cx.invalidate(3);

    if (check) {
        {
            var it = cx.dirty_set.iterator();
            while (it.next()) |kv| {
                std.log.warn("dirty: {}", .{kv.key_ptr.*});
            }
        }
        {
            for (cx.pairs.items) |kv| {
                std.log.warn("dep: {} -> {}", .{ kv[0], kv[1] });
            }
        }

        for (4..layer_count * 4) |i| {
            try std.testing.expect(cx.isDirty(i));
        }
    }

    const ns2 = timer.lap();

    try get(&cx, base_id + 0);
    try get(&cx, base_id + 1);
    try get(&cx, base_id + 2);
    try get(&cx, base_id + 3);

    if (check) for (4..layer_count * 4) |i| {
        try std.testing.expect(!cx.isDirty(i));
    };

    const ns3 = timer.lap();

    try get(&cx, base_id + 0);
    try get(&cx, base_id + 1);
    try get(&cx, base_id + 2);
    try get(&cx, base_id + 3);

    if (check) for (4..layer_count * 4) |i| {
        try std.testing.expect(!cx.isDirty(i));
    };

    const ns4 = timer.lap();

    // std.log.warn("time used: {any}", .{[_]u64{ ns_start, ns0, ns1, ns2, ns3, ns4 }});

    return ns_prepare + ns0 + ns1 + ns2 + ns3 + ns4;
}

const RUNS_PER_TIER = 150;
const LAYER_TIERS = [_]usize{
    10,
    100,
    500,
    1000,
    2000,
};

pub fn main() !void {
    // // bench
    // for (LAYER_TIERS) |n_layers| {
    //     var sum: u64 = 0;
    //     for (0..RUNS_PER_TIER) |_| {
    //         sum += try run(std.testing.allocator,n_layers, false);
    //     }
    //     const ns: f64 = @floatFromInt(sum / RUNS_PER_TIER);
    //     const ms = ns / std.time.ns_per_ms;
    //     std.log.warn("n_layers={} avg {d}ms", .{ n_layers, ms });
    // }

    while (true) {
        _ = try run(std.heap.c_allocator, 500, false);
    }
}

test "sanity check" {
    _ = try run(std.testing.allocator, 2, true);
}

// const SOLUTIONS = {
//   10: [2, 4, -2, -3],
//   100: [-2, -4, 2, 3],
//   500: [-2, 1, -4, -4],
//   1000: [-2, -4, 2, 3],
//   2000: [-2, 1, -4, -4],
//   // 2500: [-2, -4, 2, 3],
// };
