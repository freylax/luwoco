const microzig = @import("microzig");
const std = @import("std");
const drivers = microzig.drivers;
const time = drivers.time;
const Value = @import("tui/items.zig").Value;

const Self = @This();

pin: drivers.base.Digital_IO, // = null,
active: drivers.base.Digital_IO.State = .high,
buf: [3]u8 = .{ '(', 'E', ')' },
last_change: time.Absolute = .from_us(0),
is_active: bool = false,
min_switch_time: time.Duration = .from_ms(10),

pub fn readValue(self: *Self) Value {
    return .{ .ro = .{
        .size = 3,
        .ptr = self,
        .vtable = &.{ .get = getRead },
    } };
}

pub fn read(self: Self) !bool {
    const s = try self.pin.read();
    return s == self.active;
}

fn getRead(ctx: *anyopaque) []const u8 {
    const self: *Self = @ptrCast(@alignCast(ctx));
    if (self.read()) |v| {
        self.buf[1] = if (v) 'X' else 'O';
    } else |_| {
        self.buf[1] = 'E';
    }
    return &self.buf;
}

pub fn sampleValue(self: *Self) Value {
    return .{ .ro = .{
        .size = 3,
        .ptr = self,
        .vtable = &.{ .get = getSample },
    } };
}

fn getSample(ctx: *anyopaque) []const u8 {
    const self: *Self = @ptrCast(@alignCast(ctx));
    self.buf[1] = if (self.is_active) 'X' else 'O';
    return &self.buf;
}

pub const Event = enum {
    unchanged,
    changed_to_active,
    changed_to_inactive,
};

pub fn sample(self: *Self, sample_time: time.Absolute) !Event {
    const s = try self.read();
    if (s != self.is_active) {
        if (self.min_switch_time.less_than(sample_time.diff(self.last_change))) {
            self.is_active = s;
            self.last_change = sample_time;
            return if (s) .changed_to_active else .changed_to_inactive;
        }
    }
    return .unchanged;
}
