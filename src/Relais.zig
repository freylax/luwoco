const microzig = @import("microzig");
const std = @import("std");
const drivers = microzig.drivers;

const Self = @This();

pub const State = enum { off, on };
pin: drivers.base.Digital_IO,
state: State = .off,

pub fn begin(self: *Self) !void {
    try self.pin.set_direction(.output);
    try self.pin.write(.low);
}
pub fn set(self: *Self, new_state: State) !void {
    if (self.state == new_state) {
        return;
    }
    switch (new_state) {
        .off => {
            try self.pin.write(.low);
        },
        .on => {
            try self.pin.write(.high);
        },
    }
    self.state = new_state;
}
