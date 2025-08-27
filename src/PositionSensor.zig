const microzig = @import("microzig");
const std = @import("std");
const drivers = microzig.drivers;

const Self = @This();

pub const Event = enum { idle, pos, max, min };
pub const Masks = enum(u3) {
    pos = 0b001,
    min = 0b010,
    max = 0b100,
    pub fn check(mask: Masks, s: u3) bool {
        const m = @intFromEnum(mask);
        return s & m == m;
    }
};

pos_button_pin: drivers.base.Digital_IO,
min_button_pin: drivers.base.Digital_IO,
max_button_pin: drivers.base.Digital_IO,
active_state: drivers.base.Digital_IO.State = .high,

pub fn state(self: *Self) !u3 {
    var r: u3 = 0;
    const pos = try self.pos_button_pin.read();
    const min = try self.min_button_pin.read();
    const max = try self.max_button_pin.read();
    if (pos == self.active_state) {
        r |= @intFromEnum(Masks.pos);
    }
    if (min == self.active_state) {
        r |= @intFromEnum(Masks.min);
    }
    if (max == self.active_state) {
        r |= @intFromEnum(Masks.max);
    }
    return r;
}

pub fn read(self: *Self) !Event {
    const s = try state(self);
    if (Masks.min.check(s)) {
        return .min;
    }
    if (Masks.max.check(s)) {
        return .max;
    }
    if (Masks.pos.check(s)) {
        return .pos;
    }
    return .idle;
}
