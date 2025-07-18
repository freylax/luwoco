const std = @import("std");
const Value = @import("items.zig").Value;

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

pub const IntValue = struct {
    min: u8 = 0,
    max: u8,
    val: u8,
    buf: [4]u8 = [_]u8{' '} ** 4,
    // fn size(max: u8) u8 {
    //     return 1 + if (max > 99) 3 else if (max > 9) 2 else 1;
    // }
    pub fn value(self: *IntValue) Value {
        return .{
            .rw = .{
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
    fn inc(ctx: *anyopaque) void {
        const self: *IntValue = @ptrCast(@alignCast(ctx));
        if (self.val >= self.max or self.val < self.min) {
            self.val = self.min;
        } else {
            self.val += 1;
        }
    }
    fn dec(ctx: *anyopaque) void {
        const self: *IntValue = @ptrCast(@alignCast(ctx));
        if (self.val > self.max or self.val <= self.min) {
            self.val = self.max;
        } else {
            self.val -= 1;
        }
    }
};
