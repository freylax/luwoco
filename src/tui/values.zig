const std = @import("std");
const assert = std.debug.assert;
const Value = @import("items.zig").Value;
const Event = @import("Event.zig");

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

        pub fn value(self: *Self) Value {
            return .{ .ro = .{
                .size = max,
                .ptr = self,
                .vtable = &.{ .get = get },
            } };
        }

        fn get(ctx: *anyopaque) []const u8 {
            const self: *Self = @ptrCast(@alignCast(ctx));
            return map[@intFromEnum(self.ref.*)];
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

pub const IntValue = struct {
    min: u8 = 0,
    max: u8,
    val: u8,
    id: ?u16 = null,
    buf: [4]u8 = [_]u8{' '} ** 4,
    // fn size(max: u8) u8 {
    //     return 1 + if (max > 99) 3 else if (max > 9) 2 else 1;
    // }
    pub fn value(self: *IntValue) Value {
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
        const self: *IntValue = @ptrCast(@alignCast(ctx));
        _ = std.fmt.formatIntBuf(&self.buf, self.val, 10, .lower, .{ .alignment = .right, .width = 4 });
        return &self.buf;
    }
    fn event(self: *IntValue) ?Event {
        if (self.id) |id| {
            return .{ .id = id, .pl = .{ .value = self.val } };
        } else {
            return null;
        }
    }

    fn inc(ctx: *anyopaque) ?Event {
        const self: *IntValue = @ptrCast(@alignCast(ctx));
        if (self.val >= self.max or self.val < self.min) {
            self.val = self.min;
        } else {
            self.val += 1;
        }
        return self.event();
    }
    fn dec(ctx: *anyopaque) ?Event {
        const self: *IntValue = @ptrCast(@alignCast(ctx));
        if (self.val > self.max or self.val <= self.min) {
            self.val = self.max;
        } else {
            self.val -= 1;
        }
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
            _ = std.fmt.formatIntBuf(&self.buf, self.ref.*, base, .lower, .{ .alignment = .right, .width = size });
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
        id: ?u16 = null,
        buf: [3]u8 = [_]u8{' '} ** 3,
        const Opt = struct {
            db: ?u8 = null,
        };
        pub fn value(self: *Self, opt: Opt) Value {
            return .{
                .button = .{
                    .behavior = .push_button,
                    .size = self.buf.len,
                    .direct_buttons = if (opt.db) |db| &.{db} else &.{},
                    .ptr = self,
                    .vtable = &.{ .get = get, .set = set, .reset = reset, .enabled = enabled },
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
        fn enabled_(self: *Self) bool {
            return self.ref.* == self.pressed or self.ref.* == self.released;
        }
        fn enabled(ctx: *anyopaque) bool {
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
                    .vtable = &.{ .get = get, .set = set, .reset = reset, .enabled = enabled_cb },
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
        fn enabled_(self: *Self) bool {
            return self.enabled(self.ref);
        }
        fn enabled_cb(ctx: *anyopaque) bool {
            const self: *Self = @ptrCast(@alignCast(ctx));
            return enabled_(self);
        }
    };
}
