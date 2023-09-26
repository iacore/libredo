const std = @import("std");

pub fn Signal(comptime T: type) type {
    _ = T;
    return struct {
        // fn getter
        // fn setter
    };
}

pub const Scope = struct {
    a: std.mem.Allocator,
    pub fn init(a: std.mem.Allocator) @This() {
        return .{ .a = a };
    }
    pub fn deinit(this: @This()) void {
        _ = this;
    }
    pub fn createSignal(this: @This(), comptime T: type, initial_value: T) !*Signal(T) {
        _ = this;
        _ = initial_value;
    }
    pub fn createMemo(this: @This(), comptime T: type, ctx: anytype) !*Getter(T) {
        const pctx = this.a.create(@TypeOf(ctx));
        pctx.* = ctx;
        todo(this, pctx, ctx.run);
    }
};

pub const createScope = Scope.init;
