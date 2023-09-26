const std = @import("std");

pub const createScope = Scope.init;

pub fn Signal(comptime T: type) type {
    return struct {
        // borrowed
        scope: *Scope,
        // owned
        dirty: bool = false,
        value: T,

        // todo: deinit, remove from this.scope.signals

        pub fn get(this: *const @This()) T {
            this.dependency_tracker.notify(this);
            return this.value;
        }

        pub fn set(this: *@This(), new_value: T) void {
            this.value = new_value;
            this.dirty = true;
        }
    };
}

pub fn Memo(comptime T: type, comptime Context: type) type {
    return struct {
        // borrowed
        scope: *Scope,
        // owned
        dirty: bool = true,
        dependencies: std.ArrayList(*Signal),

        last_value: T,
        ctx: Context,
        fn_update: fn (*Context) T,

        // todo: deinit, remove from this.scope.memos

        pub fn get(this: *@This()) T {
            if (this.dirty) {
                defer this.dirty = false;
                this.scope.dependency_tracker.notify(this);
                this.dependencies.clearAndFree();
                this.scope.dependency_tracker.push(this);
                defer this.scope.dependency_tracker.pop();
                this.last_value = this.fn_update(&this.ctx);
            }

            return this.last_value;
        }
    };
}

// todo: make sure offsets are correct
const SignalBase = struct {
    scope: *Scope,
    dirty: bool,
};
// todo: make sure offsets are correct
const MemoBase = struct {
    scope: *Scope,
    dirty: bool,
    dependencies: std.ArrayList(*SignalBase),
};

pub const Scope = struct {
    // all owned
    a: std.mem.Allocator,
    signals: std.ArrayList(*SignalBase),
    memos: std.ArrayList(*MemoBase), // todo: evict deleted memos and signals
    dependency_tracker: *DependencyTracker,

    pub fn init(a: std.mem.Allocator) !@This() {
        const tracker = try a.create(DependencyTracker);
        tracker = DependencyTracker.init(a);
        return .{
            .a = a,
            .signals = std.ArrayList(*SignalBase).init(a),
            .memos = std.ArrayList(*MemoBase).init(a),
            .dependency_tracker = tracker,
        };
    }
    pub fn deinit(this: @This()) void {
        this.signals.deinit();
        this.memos.deinit();
        this.dependency_tracker.deinit();
    }
    pub fn createSignal(this: *@This(), comptime T: type, initial_value: T) !*Signal(T) {
        _ = this;
        _ = initial_value;
    }
    pub fn createMemo(this: *@This(), comptime T: type, ctx: anytype) !*Memo(T) {
        const pctx = this.a.create(@TypeOf(ctx));
        pctx.* = ctx;
        todo(this, pctx, ctx.run);
    }
    pub fn propagate(this: *@This()) void {
        // propagate .dirty from signals to memos
        // I hope I find a O(n) algorithm

        for (this.signals) |signal| {
            signal.dirty = false;
        }
    }
};

pub const DependencyTracker = struct {
    tracked: std.ArrayList(*MemoBase),

    pub fn init(a: std.mem.Allocator) @This() {
        return .{
            .tracked = std.ArrayList(*MemoBase).init(a),
        };
    }
    pub fn deinit(this: @This()) void {
        this.tracked.deinit();
    }

    pub fn notify(this: *@This(), signal_like: *const SignalBase) void {
        if (this.tracked.last) |memo| {
            memo.dependencies.append(signal_like) catch @panic("not enough capacity");
        }
    }

    pub fn push(this: *@This(), memo: *MemoBase) void {
        this.tracked.append(memo) catch @panic("not enough capacity");
    }
    pub fn pop(this: *@This()) void {
        this.tracked.pop();
    }
};
