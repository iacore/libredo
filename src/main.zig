const std = @import("std");

pub const SignalId = u64;

pub const DependencyTracker = struct {
    /// .{dependent, dependency}
    pub const KeyValuePair = std.meta.Tuple(&.{ SignalId, SignalId });
    pub const InitOptions = struct {
        dependent_stack_capacity: usize = 256,
        dependency_pairs_capacity: usize = 4096,
        dirty_set_capacity: u32 = 4096,
    };

    tracked: std.ArrayList(SignalId),
    pairs: std.ArrayList(KeyValuePair),
    dirty_set: std.AutoHashMap(SignalId, void),

    pub fn init(a: std.mem.Allocator, opts: InitOptions) !@This() {
        var dirty_set = std.AutoHashMap(SignalId, void).init(a);
        try dirty_set.ensureTotalCapacity(opts.dirty_set_capacity);
        return .{
            .tracked = try std.ArrayList(SignalId).initCapacity(a, opts.dependent_stack_capacity),
            .pairs = try std.ArrayList(KeyValuePair).initCapacity(a, opts.dependency_pairs_capacity),
            .dirty_set = dirty_set,
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
    pub fn setDirty(this: *@This(), dependency: SignalId, value: bool) bool {
        if (value) {
            const res = this.dirty_set.getOrPutAssumeCapacity(dependency);
            return res.found_existing;
        } else {
            return this.dirty_set.remove(dependency);
        }
    }

    /// mark that `dependency` has changed
    pub fn invalidate(this: *@This(), dependency: SignalId) void {
        for (this.pairs.items) |pair| {
            if (pair[1] == dependency and !this.setDirty(pair[0], true)) {
                this.invalidate(pair[0]);
            }
        }
    }

    /// mark that`dependency` is used
    pub fn used(this: *@This(), dependency: SignalId) void {
        if (this.tracked.getLastOrNull()) |dependent| {
            // std.log.debug("hit! {} -> {}", .{ dependent, dependency });
            this.pairs.appendAssumeCapacity(.{ dependent, dependency });
        }
    }

    /// start tracking dependencies
    pub fn begin(this: *@This(), dependent: SignalId) void {
        // clear previous dependencies
        var i: usize = 0;
        while (i < this.pairs.items.len) {
            if (this.pairs.items[i][0] == dependent) {
                _ = this.pairs.swapRemove(i);
            } else {
                i += 1;
            }
        }

        this.tracked.appendAssumeCapacity(dependent);
    }

    /// stop tracking dependencies
    pub fn end(this: *@This()) void {
        _ = this.tracked.pop();
    }
};
