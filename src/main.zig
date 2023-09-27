const std = @import("std");

pub const createScope = Scope.init;

pub fn Signal(comptime T: type) type {
    return struct {
        // owned
        header: Header(T),

        // borrowed
        scope: *Scope,

        // todo: deinit, remove from this.scope.signals

        pub fn get(this: *const @This()) T {
            this.scope.dependency_tracker.track(this);
            return this.value;
        }

        pub fn set(this: *@This(), new_value: T) void {
            this.value = new_value;
            this.scope.dependency_tracker.invalidate(this);
        }
    };
}

pub fn Header(comptime T: type) type {
    return struct {
        dirty: bool = true,
        value: T,
    };
}
pub fn Memo(comptime T: type, comptime Context: type) type {
    return struct {
        // owned
        header: Header(T),

        fn_update: *const fn (*Context) T,
        ctx: Context,

        // borrowed
        scope: *Scope,

        // todo: deinit, remove from this.scope.memos

        pub fn get(this: *@This()) T {
            this.scope.dependency_tracker.track(this);
            if (this.dirty) {
                defer this.dirty = false;
                this.scope.dependency_tracker.push(this);
                defer this.scope.dependency_tracker.pop();
                this.last_value = this.fn_update(&this.ctx);
            }

            return this.last_value;
        }
    };
}

const SignalBase = opaque {};
const MemoBase = struct {
    memo: *anyopaque,
    dirty: *bool,
};

pub const Scope = struct {
    // all owned
    a: std.mem.Allocator,
    dependency_tracker: *DependencyTracker,

    pub fn init(a: std.mem.Allocator) !@This() {
        const tracker = try a.create(DependencyTracker);
        tracker.* = try DependencyTracker.init(a);
        return .{
            .a = a,
            .dependency_tracker = tracker,
        };
    }
    pub fn deinit(this: @This()) void {
        this.dependency_tracker.deinit();
        this.a.destroy(this.dependency_tracker);
    }
    pub fn createSignal(this: *@This(), comptime T: type, initial_value: T) Signal(T) {
        return .{
            .scope = this,
            .value = initial_value,
        };
    }
    pub fn createMemo(this: *@This(), comptime T: type, ctx: anytype, fn_update: anytype) Memo(T) {
        return .{
            .dirty = true,
            .scope = this,
            .last_value = undefined,
            .ctx = ctx,
            .fn_update = fn_update,
        };
    }
};

pub const DependencyTracker = struct {
    const KeyValuePair = std.meta.Tuple(&.{ *MemoBase, *const SignalBase });

    tracked: std.ArrayList(*MemoBase),
    pairs: std.ArrayList(KeyValuePair),

    pub fn init(a: std.mem.Allocator) !@This() {
        return .{
            .tracked = try std.ArrayList(*MemoBase).initCapacity(a, 256), // todo: better memory management
            .pairs = try std.ArrayList(KeyValuePair).initCapacity(a, 4096), // todo: better memory management
        };
    }
    pub fn deinit(this: @This()) void {
        this.tracked.deinit();
        this.pairs.deinit();
    }

    pub fn invalidate(this: *@This(), signal: *const SignalBase) void {
        for (this.pairs) |pair| {
            if (pair[1] == signal and !pair[0].dirty.*) {
                pair[0].dirty.* = true;
                invalidate(pair[0]);
            }
        }
    }

    pub fn track(this: *@This(), signal: *const SignalBase) void {
        if (this.tracked.getLastOrNull()) |memo| {
            this.pairs.appendAssumeCapacity(.{ memo, signal });
        }
    }

    pub fn push(this: *@This(), memo: *MemoBase) void {
        // clear previous dependencies
        var i: usize = 0;
        while (i < this.pairs.items.len) {
            if (this.pairs.items[i][0] == memo) {
                this.pairs.swapRemove(i);
            } else {
                i += 1;
            }
        }

        this.tracked.appendAssumeCapacity(memo);
    }
    pub fn pop(this: *@This()) void {
        this.tracked.pop();
    }
};
