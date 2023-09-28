const std = @import("std");
const FieldType = std.meta.FieldType;
const assert = std.debug.assert;

pub const SignalId = u64;

/// Special two-way map
///
/// used as BijectMap(dependent, dependency)
pub fn BijectMap(comptime K: type, comptime V: type) type {
    return struct {
        //! this data structure is copied from redo and sqlite
        //! Table primary key is (target,source)

        a: std.mem.Allocator,
        arr: std.ArrayList(Entry),

        pub const Entry = std.meta.Tuple(&.{ K, V });
        pub const EntryBytes = [@sizeOf(Entry)]u8;
        fn toBytes(x: Entry) EntryBytes {
            return @as(*const EntryBytes, @ptrCast(&x)).*;
        }

        pub const Iterator = struct {
            value: V,
            slice: []const Entry,
            i: usize,

            pub fn next(this: *@This()) ?K {
                while (this.i < this.slice.len) {
                    const entry = this.slice[this.i];
                    this.i += 1;
                    if (entry[1] == this.value) return entry[0];
                }
                return null;
            }
        };

        pub fn init(a: std.mem.Allocator) @This() {
            return .{ .a = a, .arr = FieldType(@This(), .arr).init(a) };
        }
        pub fn deinit(this: @This()) void {
            this.arr.deinit();
        }
        pub fn _compareFn(_: void, lhs: Entry, rhs: Entry) std.math.Order {
            return std.mem.order(u8, &toBytes(lhs), &toBytes(rhs));
        }
        pub fn _lessThanFn(_: void, lhs: Entry, rhs: Entry) bool {
            return std.mem.lessThan(u8, &toBytes(lhs), &toBytes(rhs));
        }
        // // clears all that match (K, *)
        // pub fn clearValues(this: *@This(), key: K) void {
        //     const start = binarySearchNotGreater(Entry, Entry{ key, 0 }, this.arr.items, void{}, _compareFn);
        //     var i = start;
        //     // var i: usize = 0;
        //     var len: usize = 0;
        //     while (i < this.arr.items.len) : (i += 1) {
        //         const item = this.arr.items[i];
        //         if (item[0] == key) {
        //             len += 1;
        //         } else {
        //             break;
        //         }
        //     }
        //     if (len > 0)
        //         this.arr.replaceRange(start, len, &.{}) catch unreachable;
        // }
        // pub fn add(this: *@This(), key: K, value: V) !void {
        //     const entry = Entry{ key, value };
        //     const i = binarySearchNotGreater(Entry, entry, this.arr.items, void{}, _compareFn);
        //     const index_in_range = i < this.arr.items.len;
        //     const need_insert = if (index_in_range) !std.mem.eql(u8, &toBytes(this.arr.items[i]), &toBytes(entry)) else true;
        //     if (need_insert) {
        //         if (index_in_range) {
        //             try this.arr.insert(i, entry);
        //         } else {
        //             try std.testing.expectEqual(i, this.arr.items.len);
        //             try this.arr.append(entry);
        //         }
        //     }
        // }
        pub fn replaceValues(this: *@This(), key: K, values: []const Entry) void {
            const start = binarySearchNotGreater(Entry, Entry{ key, 0 }, this.arr.items, void{}, _compareFn);
            var i = start;
            // var i: usize = 0;
            var len: usize = 0;
            while (i < this.arr.items.len) : (i += 1) {
                const item = this.arr.items[i];
                if (item[0] == key) {
                    len += 1;
                } else {
                    break;
                }
            }
            if (len > 0 or values.len > 0)
                this.arr.replaceRange(start, len, values) catch unreachable;
        }
        pub fn clearValues(this: *@This(), key: K) void {
            this.replaceValues(key, &.{});
        }

        /// iterate all that match (*, V)
        pub fn iteratorByValue(this: @This(), value: V) ?Iterator {
            return Iterator{
                .value = value,
                .slice = this.arr.items,
                .i = 0,
            };
        }

        pub fn dumpLog(this: @This()) void {
            std.log.warn("dumpLog", .{});
            for (this.arr.items) |x| {
                std.log.warn("{} -> {}", x);
            }
        }
    };
}

pub fn binarySearchNotGreater(
    comptime T: type,
    key: anytype,
    items: []const T,
    context: anytype,
    comptime compareFn: fn (context: @TypeOf(context), key: @TypeOf(key), mid_item: T) std.math.Order,
) usize {
    var left: usize = 0;
    var right: usize = items.len;

    while (left < right) {
        // Avoid overflowing in the midpoint calculation
        const mid = left + (right - left) / 2;
        // Compare the key with the midpoint element
        switch (compareFn(context, key, items[mid])) {
            .eq => return mid,
            .gt => left = mid + 1,
            .lt => right = mid,
        }
    }

    assert(left == right);
    return left;
}

pub const DependencyMap = BijectMap(SignalId, SignalId);
pub const DependencyEntry = DependencyMap.Entry;
pub const DependencyCollector = struct {
    dependent: SignalId,
    dependencies: std.ArrayList(DependencyEntry),

    pub fn init(a: std.mem.Allocator, dependent: SignalId) @This() {
        return .{
            .dependent = dependent,
            .dependencies = FieldType(@This(), .dependencies).init(a),
        };
    }
    pub fn deinit(this: @This()) void {
        this.dependencies.deinit();
    }
    pub fn add(this: *@This(), dependency: SignalId) !void {
        try this.dependencies.append(.{ this.dependent, dependency });
    }
    pub fn getSortedList(this: @This()) []const DependencyEntry {
        std.mem.sort(DependencyEntry, this.dependencies.items, void{}, DependencyMap._lessThanFn);
        return this.dependencies.items;
    }
};

pub const DependencyTracker = struct {
    /// .{dependent, dependency}
    a: std.mem.Allocator,
    tracked: std.ArrayList(DependencyCollector),
    pairs: DependencyMap,
    dirty_set: std.AutoHashMap(SignalId, void),

    pub fn init(a: std.mem.Allocator) !@This() {
        return .{
            .a = a,
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
        this.pairs.clearValues(signal);
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
            if (!try this.setDirty(dependent, true)) {
                try this.invalidate(dependent);
            }
        }
    }

    /// mark that`dependency` is used
    pub fn used(this: *@This(), dependency: SignalId) !void {
        if (this.tracked.items.len == 0) return;
        const collector = &this.tracked.items[this.tracked.items.len - 1];
        try collector.add(dependency);
    }

    /// start tracking dependencies
    pub fn begin(this: *@This(), dependent: SignalId) !void {
        try this.tracked.append(DependencyCollector.init(this.a, dependent));
    }

    /// stop tracking dependencies
    pub fn end(this: *@This()) void {
        const collector: DependencyCollector = this.tracked.pop();
        defer collector.deinit();
        const sorted_list = collector.getSortedList();
        this.pairs.replaceValues(collector.dependent, sorted_list);
        // std.log.warn("replace({}, {any})", .{ collector.dependent, sorted_list });
    }
};
