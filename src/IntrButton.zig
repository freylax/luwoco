const microzig = @import("microzig");
const std = @import("std");
const drivers = microzig.drivers;
const Value = @import("tui/items.zig").Value;

const Self = @This();

pin: drivers.base.Digital_IO, // = null,
active: drivers.base.Digital_IO.State = .high,
buf: [3]u8 = .{ '(', 'E', ')' },

pub fn value(self: *Self) Value {
    return .{ .ro = .{
        .size = 3,
        .ptr = self,
        .vtable = &.{ .get = get },
    } };
}

pub fn read(self: Self) !bool {
    // if (self.pin) |p| {
    const s = try self.pin.read();
    return s == self.active;
    // } else {
    // return error.UninitializedPins;
    // }
}

fn get(ctx: *anyopaque) []const u8 {
    const self: *Self = @ptrCast(@alignCast(ctx));
    if (self.read()) |v| {
        self.buf[1] = if (v) 'X' else 'O';
    } else |_| {
        self.buf[1] = 'E';
    }
    return &self.buf;
}
