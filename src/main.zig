const std = @import("std");

pub const SignalId = u64;

pub const DependencyTracker = struct {
    /// .{dependent, dependency}
    pub const KeyValuePair = std.meta.Tuple(&.{ SignalId, SignalId });

    tracked: std.ArrayList(SignalId),
    pairs: std.ArrayList(KeyValuePair),
    dirty: std.AutoHashMap(SignalId, void),

    pub fn init(a: std.mem.Allocator) !@This() {
        return .{
            .tracked = try std.ArrayList(SignalId).initCapacity(a, 256), // todo: better memory management
            .pairs = try std.ArrayList(KeyValuePair).initCapacity(a, 4096), // todo: better memory management
            .dirty = std.AutoHashMap(SignalId, void).init(a),
        };
    }
    pub fn deinit(this: @This()) void {
        this.tracked.deinit();
        this.pairs.deinit();
        var dict = this.dirty;
        dict.deinit();
    }

    // pub fn isDirty(this: @This(), dependency: SignalId) bool {
    //     return this.dirty.contains(dependency);
    // }

    /// returns previous state
    pub fn setDirty(this: *@This(), dependency: SignalId, value: bool) bool {
        if (value) {
            const res = this.dirty.getOrPutAssumeCapacity(dependency);
            return res.found_existing;
        } else {
            return this.dirty.remove(dependency);
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
    pub fn track(this: *@This(), dependency: SignalId) void {
        if (this.tracked.getLastOrNull()) |memo| {
            this.pairs.appendAssumeCapacity(.{ memo, dependency });
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
