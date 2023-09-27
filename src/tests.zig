const std = @import("std");
const signals = @import("signals");

test "type check" {
    std.testing.refAllDeclsRecursive(signals);
}

// const What = [4]*signals.Header(f64);

// const Context = struct {
//     m: What,
// };

// fn run(layer_count: usize) ![4]f64 {
//     var cx = try signals.createScope(std.testing.allocator);
//     defer cx.deinit();

//     var a = cx.createSignal(f64, 1);
//     var b = cx.createSignal(f64, 2);
//     var c = cx.createSignal(f64, 3);
//     var d = cx.createSignal(f64, 4);

//     var layer: What = .{ &a.header, &b.header, &c.header, &d.header };

//     const S = struct {
//         pub fn fn_a(this: *Context) f64 {
//             return this.m[1].get();
//         }
//         pub fn fn_b(this: *Context) f64 {
//             return this.m[0].get() - this.m[2].get();
//         }
//         pub fn fn_c(this: *Context) f64 {
//             return this.m[1].get() + this.m[3].get();
//         }
//         pub fn fn_d(this: *Context) f64 {
//             return this.m[2].get();
//         }
//     };

//     for (0..layer_count) |_| {
//         layer = .{
//             cx.createMemo(f64, Context{ .m = layer }, S.fn_a),
//             cx.createMemo(f64, Context{ .m = layer }, S.fn_b),
//             cx.createMemo(f64, Context{ .m = layer }, S.fn_c),
//             cx.createMemo(f64, Context{ .m = layer }, S.fn_d),
//         };
//     }

//     var timer = try std.time.Timer.start();

//     cx.tick();
//     a.set(4);
//     b.set(3);
//     c.set(2);
//     d.set(1);

//     const end = layer;
//     const solution = [4]f64{ end[0].get(), end[1].get(), end[2].get(), end[3].get() };

//     const ns = timer.read();
//     std.log.warn("time used: {}ns", .{ns});

//     return solution;
// }

// test "100 layers" {
//     const ans = try run(100);
//     try std.testing.expectEqual([4]f64{ -2, -4, 2, 3 }, ans);
// }

// const SOLUTIONS = {
//   10: [2, 4, -2, -3],
//   100: [-2, -4, 2, 3],
//   500: [-2, 1, -4, -4],
//   1000: [-2, -4, 2, 3],
//   2000: [-2, 1, -4, -4],
//   // 2500: [-2, -4, 2, 3],
// };
