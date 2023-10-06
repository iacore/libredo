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
const SplayTree = @import("tree.zig").SplayTree;
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

        const NodeData = struct {
            key: K,
            values: []const V, // owned by BijectMap's allocator

            pub fn compare(lhs: @This(), rhs: @This()) std.math.Order {
                return std.math.order(lhs.key, rhs.key);
            }
        };
        const TreeType = SplayTree(NodeData, NodeData.compare);

        a: std.mem.Allocator,
        tree: TreeType = TreeType.init(),

        pub const Iterator = struct {
            tree: *TreeType,
            current: ?*TreeType.Node,
            i: usize = 0,
            value: V,

            pub fn next(this: *@This()) ?K {
                while (this.current) |current| {
                    for (0.., current.data.values[this.i..]) |i, v| {
                        if (v == this.value) {
                            this.i = i + 1;
                            return current.data.key;
                        }
                    }
                    this.i = 0;
                    this.current = this.tree.next(current);
                } else return null;
            }
        };

        pub fn init(a: std.mem.Allocator) @This() {
            return .{ .a = a };
        }
        pub fn deinit(this: @This()) void {
            var tree = this.tree;
            var curr = tree.min();
            while (curr) |_curr| {
                curr = tree.next(_curr);
                _ = tree.remove(_curr);
                this.freeNodeData(_curr.data);
                this.a.destroy(_curr);
            }
        }

        fn freeNodeData(this: @This(), data: NodeData) void {
            this.a.free(data.values);
        }
        /// Update dependencies of `key`
        ///
        /// `values` must be a list of `.{key, <dependency>}`
        pub fn replaceValues(this: *@This(), key: K, entries: []const V) void {
            const data = NodeData{ .key = key, .values = this.a.dupe(V, entries) catch unreachable };
            if (this.tree.find(data)) |existing| {
                this.freeNodeData(existing.data);
                existing.data = data;
            } else {
                const node = this.a.create(TreeType.Node) catch unreachable;
                node.data = data;
                _ = this.tree.insert(node);
            }
        }

        /// Query dependents of `value`. Returns `Iterator`.
        pub fn iteratorByValue(this: *@This(), value: V) ?Iterator {
            return Iterator{
                .current = this.tree.min(),
                .tree = &this.tree,
                .value = value,
            };
        }

        // pub fn _eq(lhs: Entry, rhs: Entry) bool {
        //     return std.meta.eql(lhs, rhs);
        // }
        // pub fn _compareFn(_: void, lhs: Entry, rhs: Entry) std.math.Order {
        //     return std.mem.order(u8, asBytes(&lhs), asBytes(&rhs));
        // }
        // pub fn _lessThanFn(_: void, lhs: Entry, rhs: Entry) bool {
        //     return std.mem.lessThan(u8, asBytes(&lhs), asBytes(&rhs));
        // }
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
        pub const Collector = struct {
            dependent: TaskId,
            dependencies: std.ArrayList(TaskId),

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
                try this.dependencies.append(dependency);
            }
            pub fn slice(this: @This()) []const TaskId {
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
                const new_list = collector.slice();
                this.pairs.replaceValues(collector.dependent, new_list);
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
