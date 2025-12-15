const std = @import("std");
const assert = std.debug.assert;
const items = @import("items.zig");
const Value = items.Value;
const Behaviour = items.ButtonValue.Behavior;
const Event = @import("Event.zig");
const range = @import("../range.zig");
pub const StrValue = struct {
    str: []const u8 = "Test",
    pub fn value(self: *StrValue) Value {
        return .{ .ro = .{
            .size = 4,
            .ptr = self,
            .vtable = &.{ .get = get },
        } };
    }

    fn get(ctx: *anyopaque) []const u8 {
        const self: *StrValue = @ptrCast(@alignCast(ctx));
        return self.str;
    }
};

// the enum indexes into the provided array of strings
pub fn EnumRefValue(T: type, map: anytype) type {
    const RW = enum { ro, rw };
    assert(@typeInfo(T) == .@"enum");
    // assert(@typeInfo(@TypeOf(map)) == .array);
    const en = @typeInfo(T).@"enum".fields;
    assert(en.len == map.len);
    // find the longest string
    const max = blk: {
        var n = 0;
        for (map) |m| {
            n = @max(m.len, n);
        }
        break :blk n;
    };
    return struct {
        const Self = @This();
        ref: *T,
        id: ?u16 = null,

        pub fn value(self: *Self, rw: RW) Value {
            return switch (rw) {
                .ro => .{ .ro = .{
                    .size = max,
                    .ptr = self,
                    .vtable = &.{ .get = get },
                } },
                .rw => .{ .rw = .{
                    .size = max,
                    .ptr = self,
                    .vtable = &.{ .get = get, .inc = inc, .dec = dec },
                } },
            };
        }

        fn get(ctx: *anyopaque) []const u8 {
            const self: *Self = @ptrCast(@alignCast(ctx));
            return map[@intFromEnum(self.ref.*)];
        }
        fn event(self: *Self) ?Event {
            if (self.id) |id| {
                return .{ .id = id, .pl = .value };
            } else {
                return null;
            }
        }
        fn inc(ctx: *anyopaque) ?Event {
            const self: *Self = @ptrCast(@alignCast(ctx));
            const i = @intFromEnum(self.ref.*);
            self.ref.* = @enumFromInt(if (i == en.len - 1) 0 else i + 1);
            return self.event();
        }
        fn dec(ctx: *anyopaque) ?Event {
            const self: *Self = @ptrCast(@alignCast(ctx));
            const i = @intFromEnum(self.ref.*);
            self.ref.* = @enumFromInt(if (i == 0) en.len - 1 else i - 1);
            return self.event();
        }
    };
}

pub const BulbValue = struct {
    val: bool = false,
    buf: [3]u8 = .{ '(', 'O', ')' },
    pub fn value(self: *BulbValue) Value {
        return .{ .ro = .{
            .size = 3,
            .ptr = self,
            .vtable = &.{ .get = get },
        } };
    }

    fn get(ctx: *anyopaque) []const u8 {
        const self: *BulbValue = @ptrCast(@alignCast(ctx));
        self.buf[1] = if (self.val) 'X' else 'O';
        return &self.buf;
    }
};

pub const IntValue_ = struct {
    const Self = @This();
    min: u8 = 0,
    max: u8,
    val: u8,
    id: ?u16 = null,
    buf: [4]u8 = [_]u8{' '} ** 4,
    // fn size(max: u8) u8 {
    //     return 1 + if (max > 99) 3 else if (max > 9) 2 else 1;
    // }
    pub fn value(self: *Self) Value {
        return .{
            .rw = .{
                // .id = self.id,
                .size = 4, //comptime size(self.max),
                .ptr = self,
                .vtable = &.{ .get = get, .inc = inc, .dec = dec },
            },
        };
    }
    fn get(ctx: *anyopaque) []const u8 {
        const self: *Self = @ptrCast(@alignCast(ctx));
        _ = std.fmt.printInt(&self.buf, self.val, 10, .lower, .{ .alignment = .right, .width = 4 });
        return &self.buf;
    }
    fn event(self: *Self) ?Event {
        if (self.id) |id| {
            return .{ .id = id, .pl = .value };
        } else {
            return null;
        }
    }

    fn inc(ctx: *anyopaque) ?Event {
        const self: *Self = @ptrCast(@alignCast(ctx));
        if (self.val >= self.max or self.val < self.min) {
            self.val = self.min;
        } else {
            self.val += 1;
        }
        return self.event();
    }
    fn dec(ctx: *anyopaque) ?Event {
        const self: *Self = @ptrCast(@alignCast(ctx));
        if (self.val > self.max or self.val <= self.min) {
            self.val = self.max;
        } else {
            self.val -= 1;
        }
        return self.event();
    }
};

pub fn IntValue(comptime T: type, comptime R: type, comptime size: u8, comptime base: u8) type {
    return struct {
        const Self = @This();
        const V = switch (@typeInfo(T)) {
            .pointer => |p| p.child,
            else => T,
        };
        range: range.Range(R),
        val: T,
        id: ?u16 = null,
        buf: [size]u8 = [_]u8{' '} ** size,
        pub fn value(self: *Self) Value {
            return .{
                .rw = .{
                    .size = size,
                    .ptr = self,
                    .vtable = &.{ .get = get, .inc = inc, .dec = dec },
                },
            };
        }
        fn get(ctx: *anyopaque) []const u8 {
            const self: *Self = @ptrCast(@alignCast(ctx));
            const v = switch (@typeInfo(T)) {
                .pointer => self.val.*,
                else => self.val,
            };
            _ = std.fmt.printInt(&self.buf, v, base, .lower, .{ .alignment = .right, .width = size });
            return &self.buf;
        }
        fn event(self: *Self) ?Event {
            if (self.id) |id| {
                return .{ .id = id, .pl = .value };
            } else {
                return null;
            }
        }

        fn inc(ctx: *anyopaque) ?Event {
            const self: *Self = @ptrCast(@alignCast(ctx));
            const min, const max = switch (@typeInfo(R)) {
                .pointer => .{ self.range.min.*, self.range.max.* },
                else => .{ self.range.min, self.range.max },
            };
            switch (@typeInfo(T)) {
                .pointer => {
                    if (self.val.* >= max or self.val.* < min) {
                        self.val.* = min;
                    } else {
                        self.val.* += 1;
                    }
                },
                else => {
                    if (self.val >= max or self.val < min) {
                        self.val = min;
                    } else {
                        self.val += 1;
                    }
                },
            }
            return self.event();
        }
        fn dec(ctx: *anyopaque) ?Event {
            const self: *Self = @ptrCast(@alignCast(ctx));
            const min, const max = switch (@typeInfo(R)) {
                .pointer => .{ self.range.min.*, self.range.max.* },
                else => .{ self.range.min, self.range.max },
            };
            switch (@typeInfo(T)) {
                .pointer => {
                    if (self.val.* > max or self.val.* <= min) {
                        self.val.* = max;
                    } else {
                        self.val.* -= 1;
                    }
                },
                else => {
                    if (self.val > max or self.val <= min) {
                        self.val = max;
                    } else {
                        self.val -= 1;
                    }
                },
            }
            return self.event();
        }
    };
}

pub const RefBoolValue = struct {
    const Self = @This();
    ref: *bool,
    id: ?u16 = null,
    buf: [2]u8 = [_]u8{' '} ** 2,
    pub fn value(self: *Self) Value {
        return .{
            .rw = .{
                .size = 2,
                .ptr = self,
                .vtable = &.{ .get = get, .inc = inc, .dec = dec },
            },
        };
    }
    fn get(ctx: *anyopaque) []const u8 {
        const self: *Self = @ptrCast(@alignCast(ctx));
        if (self.ref.*) {
            self.buf[1] = 'X';
        } else {
            self.buf[1] = 'O';
        }
        return &self.buf;
    }
    fn event(self: *Self) ?Event {
        if (self.id) |id| {
            return .{ .id = id, .pl = .value };
        } else {
            return null;
        }
    }
    fn inc(ctx: *anyopaque) ?Event {
        const self: *Self = @ptrCast(@alignCast(ctx));
        self.ref.* = !self.ref.*;
        return self.event();
    }
    fn dec(ctx: *anyopaque) ?Event {
        const self: *Self = @ptrCast(@alignCast(ctx));
        self.ref.* = !self.ref.*;
        return self.event();
    }
};

pub fn RoRefIntValue(comptime T: type, comptime size: u8, comptime base: u8) type {
    return struct {
        const Self = @This();
        ref: *T,
        buf: [size]u8 = [_]u8{' '} ** size,
        pub fn value(self: *Self) Value {
            return .{
                .ro = .{
                    .size = size,
                    .ptr = self,
                    .vtable = &.{ .get = get },
                },
            };
        }
        fn get(ctx: *anyopaque) []const u8 {
            const self: *Self = @ptrCast(@alignCast(ctx));
            switch (@typeInfo(T)) {
                .optional => {
                    if (self.ref.*) |v| {
                        _ = std.fmt.printInt(&self.buf, v, base, .lower, .{ .alignment = .right, .width = size });
                    } else {
                        for (0..size) |i| {
                            self.buf[i] = if (i == size / 2) '-' else ' ';
                        }
                    }
                },
                else => {
                    _ = std.fmt.printInt(&self.buf, self.ref.*, base, .lower, .{ .alignment = .right, .width = size });
                },
            }
            return &self.buf;
        }
    };
}

pub const PushButton = struct {
    val: bool = false,
    id: ?u16 = null,
    buf: [2]u8 = [_]u8{' '} ** 2,
    const Opt = struct {
        db: ?u8 = null,
    };
    pub fn value(self: *PushButton, opt: Opt) Value {
        return .{
            .button = .{
                .behavior = .push_button,
                .size = 2,
                .direct_buttons = if (opt.db) |db| &.{db} else &.{},
                .ptr = self,
                .vtable = &.{ .get = get, .set = set, .reset = reset, .enabled = enabled },
            },
        };
    }
    fn get(ctx: *anyopaque) []const u8 {
        const self: *PushButton = @ptrCast(@alignCast(ctx));
        self.buf[1] = if (self.val) 0xff else 'O';
        return &self.buf;
    }
    fn event(self: *PushButton) ?Event {
        return if (self.id) |id|
            .{ .id = id, .pl = .{ .button = self.val } }
        else
            null;
    }
    fn set(ctx: *anyopaque) ?Event {
        const self: *PushButton = @ptrCast(@alignCast(ctx));
        self.val = true;
        return self.event();
    }
    fn reset(ctx: *anyopaque) ?Event {
        const self: *PushButton = @ptrCast(@alignCast(ctx));
        self.val = false;
        return self.event();
    }
    fn toggle(ctx: *anyopaque) ?Event {
        const self: *PushButton = @ptrCast(@alignCast(ctx));
        self.val = if (self.val) false else true;
    }
    fn enabled(ctx: *anyopaque) bool {
        _ = ctx;
        return true;
    }
};

pub fn RefPushButton(comptime T: type) type {
    return struct {
        const Self = @This();
        ref: *T,
        pressed: T,
        released: T,
        enabled: ?*const fn () bool = null,
        id: ?u16 = null,
        buf: [3]u8 = [_]u8{' '} ** 3,
        const Opt = struct {
            db: ?u8 = null,
            behaviour: Behaviour = .push_button,
        };
        pub fn value(self: *Self, opt: Opt) Value {
            return .{
                .button = .{
                    .behavior = opt.behaviour,
                    .size = self.buf.len,
                    .direct_buttons = if (opt.db) |db| &.{db} else &.{},
                    .ptr = self,
                    .vtable = &.{ .get = get, .set = set, .reset = reset, .toggle = toggle, .enabled = enabledCb },
                },
            };
        }
        fn get(ctx: *anyopaque) []const u8 {
            const self: *Self = @ptrCast(@alignCast(ctx));
            if (self.enabled_()) {
                self.buf[0] = '(';
                self.buf[2] = ')';
            } else {
                self.buf[0] = '[';
                self.buf[2] = ']';
            }
            self.buf[1] = if (self.ref.* == self.pressed) '*' else 'o';
            return &self.buf;
        }
        fn event(self: *Self) ?Event {
            return if (self.id) |id|
                .{ .id = id, .pl = .{ .button = self.ref.* == self.pressed } }
            else
                null;
        }
        fn set(ctx: *anyopaque) ?Event {
            const self: *Self = @ptrCast(@alignCast(ctx));
            self.ref.* = self.pressed;
            return self.event();
        }
        fn reset(ctx: *anyopaque) ?Event {
            const self: *Self = @ptrCast(@alignCast(ctx));
            self.ref.* = self.released;
            return self.event();
        }
        fn toggle(ctx: *anyopaque) ?Event {
            const self: *Self = @ptrCast(@alignCast(ctx));
            self.ref.* = if (self.ref.* == self.pressed) self.released else self.pressed;
            return self.event();
        }
        fn enabled_(self: *Self) bool {
            if (self.enabled) |cb| {
                return cb();
            } else {
                return self.ref.* == self.pressed or self.ref.* == self.released;
            }
        }
        fn enabledCb(ctx: *anyopaque) bool {
            const self: *Self = @ptrCast(@alignCast(ctx));
            return enabled_(self);
        }
    };
}
pub fn ClickButton(comptime T: type) type {
    return struct {
        const Self = @This();
        ref: *T,
        enabled: *const fn (*T) bool,
        clicked: *const fn (*T) void,
        id: ?u16 = null,
        buf: [3]u8 = [_]u8{' '} ** 3,
        pressed: bool = false,
        pub const Opt = struct {
            db: ?u8 = null,
        };
        pub fn value(self: *Self, opt: Opt) Value {
            return .{
                .button = .{
                    .behavior = .one_click,
                    .size = self.buf.len,
                    .direct_buttons = if (opt.db) |db| &.{db} else &.{},
                    .ptr = self,
                    .vtable = &.{ .get = get, .set = set, .reset = reset, .toggle = toggle, .enabled = enabled_cb },
                },
            };
        }
        fn get(ctx: *anyopaque) []const u8 {
            const self: *Self = @ptrCast(@alignCast(ctx));
            if (self.enabled_()) {
                self.buf[0] = '(';
                self.buf[2] = ')';
            } else {
                self.buf[0] = '[';
                self.buf[2] = ']';
            }
            self.buf[1] = if (self.pressed) '*' else 'o';
            return &self.buf;
        }
        fn event(self: *Self) ?Event {
            return if (self.id) |id|
                .{ .id = id, .pl = .{ .button = self.pressed } }
            else
                null;
        }
        fn set(ctx: *anyopaque) ?Event {
            const self: *Self = @ptrCast(@alignCast(ctx));
            self.pressed = true;
            self.clicked(self.ref);
            return self.event();
        }
        fn reset(ctx: *anyopaque) ?Event {
            const self: *Self = @ptrCast(@alignCast(ctx));
            self.pressed = false;
            return self.event();
        }
        // tihs is a dummy implementation
        fn toggle(ctx: *anyopaque) ?Event {
            const self: *Self = @ptrCast(@alignCast(ctx));
            return self.event();
        }
        fn enabled_(self: *Self) bool {
            return self.enabled(self.ref);
        }
        fn enabled_cb(ctx: *anyopaque) bool {
            const self: *Self = @ptrCast(@alignCast(ctx));
            return enabled_(self);
        }
    };
}
