const microzig = @import("microzig");
const std = @import("std");
const drivers = microzig.drivers;

const Self = @This();

pub const State = enum { off, dir_a, dir_b };
enable_pin: drivers.base.Digital_IO,
dir_a_pin: drivers.base.Digital_IO,
dir_b_pin: drivers.base.Digital_IO,
state: State = .off,

pub fn begin(self: *Self) !void {
    try self.enable_pin.set_direction(.output);
    try self.enable_pin.write(.low);
    try self.dir_a_pin.set_direction(.output);
    try self.dir_a_pin.write(.low);
    try self.dir_b_pin.set_direction(.output);
    try self.dir_b_pin.write(.low);
}
pub fn set(self: *Self, new_state: State) !void {
    if (self.state == new_state) {
        return;
    }
    switch (self.state) {
        .off => {},
        .dir_a => {
            try self.enable_pin.write(.low);
            try self.dir_a_pin.write(.low);
        },
        .dir_b => {
            try self.enable_pin.write(.low);
            try self.dir_b_pin.write(.low);
        },
    }
    switch (new_state) {
        .off => {},
        .dir_a => {
            try self.dir_a_pin.write(.high);
            try self.enable_pin.write(.high);
        },
        .dir_b => {
            try self.dir_b_pin.write(.high);
            try self.enable_pin.write(.high);
        },
    }
    self.state = new_state;
}
