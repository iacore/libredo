const std = @import("std");
const FieldType = std.meta.FieldType;
const assert = std.debug.assert;

pub const SignalId = u64;

/// Special two-way map
///
/// used as BijectMap(dependent, dependency)
pub fn BijectMap(comptime K: type, comptime V: type) type {
    return struct {
        a: std.mem.Allocator,
        k2v: std.AutoHashMap(K, std.AutoHashMap(V, void)),
        v2k: std.AutoHashMap(V, std.AutoHashMap(K, void)),

        pub const KSet = std.AutoHashMap(K, void);
        pub const VSet = std.AutoHashMap(V, void);
        pub const Iterator = KSet.KeyIterator;

        pub fn init(a: std.mem.Allocator) @This() {
            return .{
                .a = a,
                .k2v = FieldType(@This(), .k2v).init(a),
                .v2k = FieldType(@This(), .v2k).init(a),
            };
        }
        pub fn deinit(this: @This()) void {
            var _this = this;
            {
                var it = _this.k2v.valueIterator();
                while (it.next()) |arr| arr.deinit();
                _this.k2v.deinit();
            }
            {
                var it = _this.v2k.valueIterator();
                while (it.next()) |arr| arr.deinit();
                _this.v2k.deinit();
            }
        }

        pub const ClearOptions = struct {
            ret_vset_ptr: ?**VSet = null,
            retain_memory: bool = true,
            assert_empty: bool = false,
        };
        pub fn clearValues(this: *@This(), key: K, opts: ClearOptions) !void {
            const entry = if (opts.retain_memory) (this.k2v.getEntry(key) orelse return) else blk: {
                const set = try this.k2v.getOrPut(key);
                if (!set.found_existing) setzig build.value_ptr.* = @TypeOf(set.value_ptr.*).init(this.a);
                break :blk @TypeOf(this.k2v).Entry{
                    .key_ptr = set.key_ptr,
                    .value_ptr = set.value_ptr,
                };
            };
            const values_map = entry.value_ptr;
            defer {
                if (opts.retain_memory) {
                    values_map.clearRetainingCapacity();
                } else {
                    assert(opts.ret_vset_ptr == null);
                    this.k2v.removeByPtr(entry.key_ptr);
                    values_map.deinit();
                }
            }
            if (opts.ret_vset_ptr) |ret| ret.* = values_map;

            if (opts.assert_empty)
                assert(values_map.count() == 0);

            var it = values_map.keyIterator();
            while (it.next()) |value| {
                const entry_set = this.v2k.getEntry(value.*) orelse unreachable;
                const set = entry_set.value_ptr;
                defer {
                    if (set.count() == 0) {
                        if (opts.retain_memory) {
                            set.clearRetainingCapacity();
                        } else {
                            set.deinit();
                            this.v2k.removeByPtr(entry_set.key_ptr);
                        }
                    }
                }
                const remove_ok = set.remove(key);
                if (!remove_ok) unreachable;
            }
        }
        pub fn add(this: *@This(), key: K, key_vset: *VSet, value: V) !void {
            {
                try key_vset.put(value, void{});
            }
            {
                const entry = try this.v2k.getOrPut(value);
                if (!entry.found_existing) {
                    entry.value_ptr.* = @TypeOf(entry.value_ptr.*).init(this.a);
                }
                try entry.value_ptr.put(key, void{});
            }
        }
        /// iterate keys that has value
        pub fn iteratorByValue(this: *const @This(), value: V) ?Iterator {
            const keys = this.v2k.get(value) orelse return null;
            return keys.keyIterator();
        }
        pub fn dumpLog(this: @This()) void {
            {
                std.log.warn("k2v:", .{});
                var it = this.k2v.iterator();
                while (it.next()) |entry| {
                    const key = entry.key_ptr.*;

                    var it1 = entry.value_ptr.*.iterator();
                    while (it1.next()) |entry1| {
                        const value = entry1.key_ptr.*;
                        std.log.warn("{} -> {}", .{ key, value });
                    }
                }
            }
            {
                std.log.warn("v2k:", .{});
                var it = this.v2k.iterator();
                while (it.next()) |entry| {
                    const key = entry.key_ptr.*;

                    var it1 = entry.value_ptr.*.iterator();
                    while (it1.next()) |entry1| {
                        const value = entry1.key_ptr.*;
                        std.log.warn("{} -> {}", .{ key, value });
                    }
                }
            }
        }
    };
}

pub const DependencyTracker = struct {
    pub const VSet = BijectMap(SignalId, SignalId).VSet;
    pub const TrackEntry = struct {
        signal: SignalId,
        key_vset: *VSet,
    };

    tracked: std.ArrayList(TrackEntry),
    pairs: BijectMap(SignalId, SignalId),
    dirty_set: std.AutoHashMap(SignalId, void),

    pub fn init(a: std.mem.Allocator) !@This() {
        return .{
            .tracked = FieldType(@This(), .tracked).init(a),
            .pairs = FieldType(@This(), .pairs).init(a),
            .dirty_set = FieldType(@This(), .dirty_set).init(a),
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
        this.pairs.clearValues(signal, .{ .retain_memory = false, .assert_empty = true }) catch unreachable;
    }
    // only memos need to be registered
    pub fn register(this: *@This(), signal: SignalId) !void {
        const res = try this.setDirty(signal, true);
        if (res) std.debug.panic("Signal already registered: {}", .{signal});
    }

    /// mark that `dependency` has changed
    pub fn invalidate(this: *@This(), dependency: SignalId) !void {
        var it = this.pairs.iteratorByValue(dependency) orelse return;
        while (it.next()) |dependent| {
            if (!try this.setDirty(dependent.*, true)) {
                try this.invalidate(dependent.*);
            }
        }
    }

    /// mark that`dependency` is used
    pub fn used(this: *@This(), dependency: SignalId) !void {
        if (this.tracked.getLastOrNull()) |dependent| {
            try this.pairs.add(dependent.signal, dependent.key_vset, dependency);
        }
    }

    /// start tracking dependencies
    pub fn begin(this: *@This(), dependent: SignalId) !void {
        var key_vset: *VSet = undefined;
        try this.pairs.clearValues(dependent, .{ .ret_vset_ptr = &key_vset });

        try this.tracked.append(.{ .signal = dependent, .key_vset = key_vset });
    }

    /// stop tracking dependencies
    pub fn end(this: *@This()) void {
        _ = this.tracked.pop();
    }
};
