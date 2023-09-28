const std = @import("std");
const FieldType = std.meta.FieldType;
const assert = std.debug.assert;

/// Special two-way map for dependency tracking
/// Please use as BijectMap(dependent, dependency)
///
/// The data structure is adapted from redo-python and sqlite
/// Important functions:
/// - replaceValues
/// - [`iteratorByValue`]
pub fn BijectMap(comptime K: type, comptime V: type) type {
    return struct {
        const _important_api = .{
            replaceValues,
        };

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

        /// Update dependencies of `key`
        ///
        /// `values` must be a list of `.{key, <dependency>}`
        pub fn replaceValues(this: *@This(), key: K, entries: []const Entry) void {
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
            for (entries) |entry| {
                assert(entry[0] == key);
            }
            if (len > 0 or entries.len > 0)
                this.arr.replaceRange(start, len, entries) catch unreachable;
        }

        /// Query dependents of `value`. Returns `Iterator`.
        pub fn iteratorByValue(this: @This(), value: V) ?Iterator {
            return Iterator{
                .value = value,
                .slice = this.arr.items,
                .i = 0,
            };
        }

        pub fn _eq(lhs: Entry, rhs: Entry) bool {
            return std.mem.eql(u8, &toBytes(lhs), &toBytes(rhs));
        }
        pub fn _compareFn(_: void, lhs: Entry, rhs: Entry) std.math.Order {
            return std.mem.order(u8, &toBytes(lhs), &toBytes(rhs));
        }
        pub fn _lessThanFn(_: void, lhs: Entry, rhs: Entry) bool {
            return std.mem.lessThan(u8, &toBytes(lhs), &toBytes(rhs));
        }
        /// debug only
        pub fn _dumpLog(this: @This()) void {
            std.log.warn("dumpLog", .{});
            for (this.arr.items) |x| {
                std.log.warn("{} -> {}", x);
            }
        }
    };
}

// helper
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

/// Construct a dependency-tracking module
/// `id_type`: signal/task id type. Should be integer like u64. Smaller is better (saves memory).
///
/// Returns a struct filled with types.
pub fn dependency_module(comptime id_type: type) type {
    return struct {
        pub const NodeId = id_type;
        pub const Map = BijectMap(NodeId, NodeId);
        pub const Entry = Map.Entry;
        pub const Collector = struct {
            dependent: NodeId,
            dependencies: std.ArrayList(Entry),

            pub fn init(a: std.mem.Allocator, dependent: NodeId) @This() {
                return .{
                    .dependent = dependent,
                    .dependencies = FieldType(@This(), .dependencies).init(a),
                };
            }
            pub fn deinit(this: @This()) void {
                this.dependencies.deinit();
            }
            pub fn add(this: *@This(), dependency: NodeId) !void {
                try this.dependencies.append(.{ this.dependent, dependency });
            }
            pub fn getSortedList(this: @This()) []const Entry {
                std.mem.sort(Entry, this.dependencies.items, void{}, Map._lessThanFn);
                return this.dependencies.items;
            }
        };

        pub const Tracker = struct {
            /// .{dependent, dependency}
            a: std.mem.Allocator,
            tracked: std.ArrayList(Collector),
            pairs: Map,
            dirty_set: std.AutoHashMap(NodeId, void),

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

            pub fn isDirty(this: @This(), dependency: NodeId) bool {
                return this.dirty_set.contains(dependency);
            }

            /// returns previous state
            pub fn setDirty(this: *@This(), dependency: NodeId, value: bool) !bool {
                if (value) {
                    const res = try this.dirty_set.getOrPut(dependency);
                    return res.found_existing;
                } else {
                    return this.dirty_set.remove(dependency);
                }
            }

            pub fn unregister(this: *@This(), signal: NodeId) void {
                this.pairs.replaceValues(signal, &.{});
            }
            // only memos need to be registered
            pub fn register(this: *@This(), signal: NodeId) !void {
                const res = try this.setDirty(signal, true);
                if (res) std.debug.panic("Signal already registered: {}", .{signal});
            }

            /// mark that `dependency` has changed
            pub fn invalidate(this: *@This(), dependency: NodeId) !void {
                var it = this.pairs.iteratorByValue(dependency) orelse return;
                while (it.next()) |dependent| {
                    if (!try this.setDirty(dependent, true)) {
                        try this.invalidate(dependent);
                    }
                }
            }

            /// mark that`dependency` is used
            pub fn used(this: *@This(), dependency: NodeId) !void {
                if (this.tracked.items.len == 0) return;
                const collector = &this.tracked.items[this.tracked.items.len - 1];
                try collector.add(dependency);
            }

            /// start tracking dependencies
            pub fn begin(this: *@This(), dependent: NodeId) !void {
                try this.tracked.append(Collector.init(this.a, dependent));
            }

            /// stop tracking dependencies
            pub fn end(this: *@This()) void {
                const collector: Collector = this.tracked.pop();
                defer collector.deinit();
                const sorted_list = collector.getSortedList();
                this.pairs.replaceValues(collector.dependent, sorted_list);
                // std.log.warn("replace({}, {any})", .{ collector.dependent, sorted_list });
            }
        };
    };
}
