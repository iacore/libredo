//! Dependency tracking library supporting cyclic dependencies
test "Table Of Contents" {
    _ = .{
        // Dependency graph as trie, for direct dependency tracking
        // If you are building a build system, this is what you need
        BijectMap(u64, u64),

        // redo/Solid.JS-like automatic dependency tracker.
        // Data not included (you need to manage data yourself).
        dependency_module(u64).Tracker,
    };
}

const std = @import("std");
const FieldType = std.meta.FieldType;
const assert = std.debug.assert;
const asBytes = std.mem.asBytes;

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
            return std.meta.eql(lhs, rhs);
        }
        pub fn _compareFn(_: void, lhs: Entry, rhs: Entry) std.math.Order {
            return std.mem.order(u8, asBytes(&lhs), asBytes(&rhs));
        }
        pub fn _lessThanFn(_: void, lhs: Entry, rhs: Entry) bool {
            return std.mem.lessThan(u8, asBytes(&lhs), asBytes(&rhs));
        }
        /// print debug info
        pub fn _dumpLog(this: @This()) void {
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
        pub const TaskId = id_type;
        pub const Map = BijectMap(TaskId, TaskId);
        pub const Entry = Map.Entry;
        pub const Collector = struct {
            dependent: TaskId,
            dependencies: std.ArrayList(Entry),

            pub fn init(a: std.mem.Allocator, dependent: TaskId) @This() {
                return .{
                    .dependent = dependent,
                    .dependencies = FieldType(@This(), .dependencies).init(a),
                };
            }
            pub fn deinit(this: @This()) void {
                this.dependencies.deinit();
            }
            pub fn add(this: *@This(), dependency: TaskId) !void {
                try this.dependencies.append(.{ this.dependent, dependency });
            }
            pub fn getSortedList(this: @This()) []const Entry {
                std.mem.sort(Entry, this.dependencies.items, void{}, Map._lessThanFn);
                return this.dependencies.items;
            }
        };

        /// Auto Depnedency Tracker like Solid.JS
        ///
        /// For usage, check below.
        ///
        /// For example, please refer to function `run` in tests.zig for usage.
        pub const Tracker = struct {
            test "Usage" {
                _ = .{
                    // Register tasks
                    register,
                    unregister,
                    //
                    // Query and set task status
                    isDirty,
                    setDirty,
                    invalidate,
                    //
                    // Tracking dependencies
                    begin,
                    end,
                    used,
                };
            }

            a: std.mem.Allocator,
            tracked: std.ArrayList(Collector),
            pairs: Map,
            dirty_set: std.AutoHashMap(TaskId, void),

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

            /// register non-source task
            ///
            /// source tasks (ones that do not depend on anything) do not need to be registered
            pub fn register(this: *@This(), task_id: TaskId) !void {
                const res = try this.setDirty(task_id, true);
                if (res) std.debug.panic("task_id already registered: {}", .{task_id});
            }
            /// unregister non-source task
            pub fn unregister(this: *@This(), task_id: TaskId) void {
                this.pairs.replaceValues(task_id, &.{});
            }

            /// check if the task need to be re-run
            pub fn isDirty(this: @This(), dependency: TaskId) bool {
                return this.dirty_set.contains(dependency);
            }

            /// set task dirty state, returns previous state
            pub fn setDirty(this: *@This(), dependency: TaskId, value: bool) !bool {
                if (value) {
                    const res = try this.dirty_set.getOrPut(dependency);
                    return res.found_existing;
                } else {
                    return this.dirty_set.remove(dependency);
                }
            }

            /// mark that the task has changed
            pub fn invalidate(this: *@This(), dependency: TaskId) !void {
                var it = this.pairs.iteratorByValue(dependency) orelse return;
                while (it.next()) |dependent| {
                    if (!try this.setDirty(dependent, true)) {
                        try this.invalidate(dependent);
                    }
                }
            }

            /// start tracking dependencies
            pub fn begin(this: *@This(), dependent: TaskId) !void {
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

            /// mark that`dependency` is used
            pub fn used(this: *@This(), dependency: TaskId) !void {
                if (this.tracked.items.len == 0) return;
                const collector = &this.tracked.items[this.tracked.items.len - 1];
                try collector.add(dependency);
            }

            /// print debug info
            pub fn _dumpLog(this: @This()) void {
                std.log.warn("#dep={} #dirty={}", .{ this.pairs.arr.items.len, this.dirty_set.count() });
                this.pairs._dumpLog();
                var it = this.dirty_set.iterator();
                while (it.next()) |kv| {
                    std.log.warn("dirty: {}", .{kv.key_ptr.*});
                }
            }
        };
    };
}
