const std = @import("std");
const signals = @import("signals");

fn run(layer_count: usize) ![4]f64 {
    const cx = signals.createScope(std.testing.allocator);
    defer cx.deinit();

    const a = try cx.createSignal(f64, 1);
    const b = try cx.createSignal(f64, 2);
    const c = try cx.createSignal(f64, 3);
    const d = try cx.createSignal(f64, 4);

    const What = [4]signals.Getter(f64);
    var layer: What = .{ a, b, c, d };

    for (0..layer_count) |_| {
        layer = .{
            try cx.createMemo(f64, struct {
                m: What,
                pub fn run(this: *@This()) f64 {
                    return this.m[1].get();
                }
            }{ .m = layer }),
            try cx.createMemo(f64, struct {
                m: What,
                pub fn run(this: *@This()) f64 {
                    return this.m[0].get() - this.m[2].get();
                }
            }{ .m = layer }),
            try cx.createMemo(f64, struct {
                m: What,
                pub fn run(this: *@This()) f64 {
                    return this.m[1].get() + this.m[3].get();
                }
            }{ .m = layer }),
            try cx.createMemo(f64, struct {
                m: What,
                pub fn run(this: *@This()) f64 {
                    return this.m[2].get();
                }
            }{ .m = layer }),
        };
    }

    var timer = try std.time.Timer.start();

    cx.tick();
    a.set(4);
    b.set(3);
    c.set(2);
    d.set(1);

    const end = layer;
    const solution = [4]f64{ end[0].get(), end[1].get(), end[2].get(), end[3].get() };

    const ns = timer.read();
    std.log.warn("time used: {}ns", .{ns});

    return solution;
}

test "100 layers" {
    const ans = try run(100);
    try std.testing.expectEqual([4]f64{ -2, -4, 2, 3 }, ans);
}

// const SOLUTIONS = {
//   10: [2, 4, -2, -3],
//   100: [-2, -4, 2, 3],
//   500: [-2, 1, -4, -4],
//   1000: [-2, -4, 2, 3],
//   2000: [-2, 1, -4, -4],
//   // 2500: [-2, -4, 2, 3],
// };
