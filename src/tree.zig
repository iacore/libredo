//! This file defines data structures for different types of trees:
//! splay trees.

const std = @import("std");

const WhichEnd = enum { min, max };

pub fn SplayTree(comptime T: type, comptime cmp: fn (T, T) std.math.Order) type {
    return struct {
        //! A splay tree is a self-organizing data structure.  Every operation
        //! on the tree causes a splay to happen.  The splay moves the requested
        //! node to the root of the tree and partly rebalances it.
        //!
        //! This has the benefit that request locality causes faster lookups as
        //! the requested nodes move to the top of the tree.  On the other hand,
        //! every lookup causes memory writes.
        //!
        //! The Balance Theorem bounds the total access time for m operations
        //! and n inserts on an initially empty tree as O((m + n)lg n).  The
        //! amortized cost for a sequence of m accesses to a splay tree is O(lg n);

        root: ?*Node = null,

        pub const Node = struct {
            data: T,
            left: ?*@This() = null,
            right: ?*@This() = null,
        };

        pub fn init() @This() {
            return .{};
        }
        pub fn isEmpty(head: @This()) bool {
            return head.root == null;
        }

        pub fn min(head: *@This()) ?*Node {
            if (head.isEmpty()) return null;
            splay_minmax(head, .min);
            return head.root;
        }
        pub fn max(head: *@This()) ?*Node {
            if (head.isEmpty()) return null;
            splay_minmax(head, .max);
            return head.root;
        }
        pub fn find(head: *@This(), elm: T) ?*Node {
            if (head.isEmpty()) return null;
            splay(head, elm);
            if (cmp(elm, head.root.?.data) == .eq) return head.root;
            return null;
        }
        pub fn next(head: *@This(), elm: *Node) ?*Node {
            splay(head, elm.data);
            if (elm.right) |child| {
                var elm_ = child;
                while (elm_.left) |closer| {
                    elm_ = closer;
                }
                return elm_;
            } else return null;
        }
        pub fn prev(head: *@This(), elm: *Node) ?*Node {
            splay(head, elm.data);
            if (elm.left) |child| {
                var elm_ = child;
                while (elm_.right) |closer| {
                    elm_ = closer;
                }
                return elm_;
            } else return null;
        }
        // returns if existing node exists
        pub fn insert(head: *@This(), elm: *Node) ?*Node {
            if (head.isEmpty()) {
                elm.left = null; // ???
                elm.right = null; // ???
            } else {
                splay(head, elm.data);
                switch (cmp(elm.data, head.root.?.data)) {
                    .lt => {
                        elm.left = head.root.?.left;
                        elm.right = head.root;
                        head.root.?.left = null;
                    },
                    .gt => {
                        elm.right = head.root.?.right;
                        elm.left = head.root;
                        head.root.?.right = null;
                    },
                    .eq => {
                        return head.root;
                    },
                }
            }
            head.root = elm;
            return null;
        }
        pub fn remove(head: *@This(), elm: *Node) ?*Node {
            if (head.isEmpty()) return null;
            splay(head, elm.data);
            if (cmp(elm.data, head.root.?.data) == .eq) {
                if (head.root.?.left == null) {
                    head.root = head.root.?.right;
                } else {
                    const tmp = head.root.?.right;
                    head.root = head.root.?.left;
                    splay(head, elm.data);
                    head.root.?.right = tmp;
                }
                return elm;
            }
            return null;
        }

        // rotate{Right,Left} expect that tmp hold {.right,.left}
        fn rotateRight(head: *@This(), tmp: *Node) void {
            head.root.?.left = tmp.right;
            tmp.right = head.root;
            head.root = tmp;
        }
        fn rotateLeft(head: *@This(), tmp: *Node) void {
            head.root.?.right = tmp.left;
            tmp.left = head.root;
            head.root = tmp;
        }
        fn linkLeft(head: *@This(), tmp: **Node) void {
            tmp.*.left = head.root;
            tmp.* = head.root.?;
            head.root = head.root.?.left;
        }
        fn linkRight(head: *@This(), tmp: **Node) void {
            tmp.*.right = head.root;
            tmp.* = head.root.?;
            head.root = head.root.?.right;
        }
        fn assemble(head: *@This(), node: *Node, left: *Node, right: *Node) void {
            left.right = head.root.?.left;
            right.left = head.root.?.right;
            head.root.?.left = node.right;
            head.root.?.right = node.left;
        }
        fn splay(head: *@This(), elm: T) void {
            var node: Node = undefined;
            node.left = null;
            node.right = null;

            var left: *Node = &node;
            var right: *Node = &node;
            var tmp: ?*Node = undefined;

            var comp: std.math.Order = undefined;
            while (blk: {
                comp = cmp(elm, head.root.?.data);
                break :blk comp != .eq;
            }) {
                switch (comp) {
                    .lt => {
                        tmp = head.root.?.left;
                        if (tmp == null) break;
                        if (cmp(elm, tmp.?.data) == .lt) {
                            rotateRight(head, tmp.?);
                            if (head.root.?.left == null) break;
                        }
                        linkLeft(head, &right);
                    },
                    .gt => {
                        tmp = head.root.?.right;
                        if (tmp == null) break;
                        if (cmp(elm, tmp.?.data) == .gt) {
                            rotateLeft(head, tmp.?);
                            if (head.root.?.right == null) break;
                        }
                        linkRight(head, &left);
                    },
                    .eq => {},
                }
            }
            assemble(head, &node, left, right);
        }
        /// Splay with either the minimum or the maximum element
        /// Used to find minimum or maximum element in tree.
        fn splay_minmax(head: *@This(), comp: WhichEnd) void {
            var node: Node = undefined;
            node.left = null;
            node.right = null;

            var left: *Node = &node;
            var right: *Node = &node;
            var tmp: ?*Node = undefined;

            while (true) {
                switch (comp) {
                    .min => {
                        tmp = head.root.?.left;
                        if (tmp == null) break;
                        if (comp == .min) { // ???
                            rotateRight(head, tmp.?);
                            if (head.root.?.left == null) break;
                        }
                        linkLeft(head, &right);
                    },
                    .max => {
                        tmp = head.root.?.right;
                        if (tmp == null) break;
                        if (comp == .max) { // ???
                            rotateLeft(head, tmp.?);
                            if (head.root.?.right == null) break;
                        }
                        linkRight(head, &left);
                    },
                }
            }
            assemble(head, &node, left, right);
        }
    };
}

const t = std.testing;

fn _cmp_Entry_u8(lhs: u8, rhs: u8) std.math.Order {
    return std.math.order(lhs, rhs);
}
test "foreach" {
    const Tree = SplayTree(u8, _cmp_Entry_u8);
    var tree = Tree.init();
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    for (0..10) |i| {
        const node = try arena.allocator().create(Tree.Node);
        node.data = @intCast(i);
        const existing = tree.insert(node);
        try t.expectEqual(@as(?*Tree.Node, null), existing);
    }

    // iterate min to max
    {
        var i: u8 = 0;
        var x = tree.min();
        while (x) |_x| : ({
            x = tree.next(_x);
            i += 1;
        }) {
            try t.expectEqual(i, _x.data);
        }
        try t.expectEqual(@as(u8, 10), i);
    }

    // iterate max to min
    {
        var i: u8 = 0;
        var x = tree.max();
        while (x) |_x| : ({
            x = tree.prev(_x);
            i += 1;
        }) {
            try t.expectEqual(9 - i, _x.data);
        }
        try t.expectEqual(@as(u8, 10), i);
    }

    // find
    for (0..10) |i| {
        const node = tree.find(@intCast(i));
        _ = node.?;
    }
}

test "how to free nodes correctly" {
    const Tree = SplayTree(u8, _cmp_Entry_u8);
    var tree = Tree.init();

    // insert nodes
    for (0..10) |i| {
        const node = try t.allocator.create(Tree.Node);
        node.data = @intCast(i);
        const existing = tree.insert(node);
        try t.expectEqual(@as(?*Tree.Node, null), existing);
    }

    // free nodes
    var x = tree.min();
    while (x) |_x| {
        x = tree.next(_x); // must do it before the node is freed
        const _x_dup = tree.remove(_x);
        try t.expectEqual(_x, _x_dup.?);
        t.allocator.destroy(_x);
    }
}
