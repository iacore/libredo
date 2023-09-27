const std = @import("std");

pub const SignalId = u64;

/// Special two-way map
///
/// used as BijectMap(dependent, dependency)
pub fn BijectMap(comptime K: type, comptime V: type) type {
    return struct {
        pub const Iterator = struct {
            pub fn next(this: *@This()) ?K {
                _ = this;
                return undefined;
            }
        };

        pub fn init(a: std.mem.Allocator) @This() {
            _ = a;
            return .{};
        }
        pub fn deinit(this: @This()) void {
            _ = this;
        }

        pub fn clearValues(this: *@This(), key: K) void {
            _ = key;
            _ = this;
        }
        pub fn add(this: *@This(), key: K, value: V) !void {
            _ = value;
            _ = key;
            _ = this;
        }
        /// iterate keys that has value
        pub fn iteratorByValue(this: *const @This(), value: V) Iterator {
            _ = value;
            _ = this;
            return .{};
        }
    };
}

pub const DependencyTracker = struct {
    /// .{dependent, dependency}
    pub const KeyValuePair = std.meta.Tuple(&.{ SignalId, SignalId });

    tracked: std.ArrayList(SignalId),
    pairs: BijectMap(SignalId, SignalId),
    dirty_set: std.AutoHashMap(SignalId, void),

    pub fn init(a: std.mem.Allocator) !@This() {
        const _p: @This() = undefined;
        return .{
            .tracked = @TypeOf(_p.tracked).init(a),
            .pairs = @TypeOf(_p.pairs).init(a),
            .dirty_set = @TypeOf(_p.dirty_set).init(a),
        };
    }
    pub fn deinit(this: @This()) void {
        this.tracked.deinit();
        this.pairs.deinit();
        var dict = this.dirty_set;
        dict.deinit();
    }

    pub fn isDirty(this: @This(), dependency: SignalId) bool {
        return this.dirty_set.contains(dependency);
    }

    /// returns previous state
    pub fn setDirty(this: *@This(), dependency: SignalId, value: bool) !bool {
        if (value) {
            const res = try this.dirty_set.getOrPut(dependency);
            return res.found_existing;
        } else {
            return this.dirty_set.remove(dependency);
        }
    }

    pub fn unregister(this: *@This(), signal: SignalId) void {
        this.pairs.clearValues(signal);
        // todo: check if any dependent of `signal` is still registered, and warn
    }
    pub fn register(this: *@This(), signal: SignalId) !void {
        const res = try this.setDirty(signal, true);
        if (res) std.debug.panic("Signal already registered: {}", .{signal});
    }

    /// mark that `dependency` has changed
    pub fn invalidate(this: *@This(), dependency: SignalId) !void {
        var it = this.pairs.iteratorByValue(dependency);
        while (it.next()) |dependent| {
            if (!try this.setDirty(dependent, true)) {
                try this.invalidate(dependent);
            }
        }
    }

    /// mark that`dependency` is used
    pub fn used(this: *@This(), dependency: SignalId) !void {
        if (this.tracked.getLastOrNull()) |dependent| {
            try this.pairs.add(dependent, dependency);
        }
    }

    /// start tracking dependencies
    pub fn begin(this: *@This(), dependent: SignalId) !void {
        this.pairs.clearValues(dependent);

        try this.tracked.append(dependent);
    }

    /// stop tracking dependencies
    pub fn end(this: *@This()) void {
        _ = this.tracked.pop();
    }
};
