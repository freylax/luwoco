const microzig = @import("microzig");
const std = @import("std");
const drivers = microzig.drivers;

const Self = @This();

pub const State = enum { off, dir_a, dir_b };
enable: drivers.base.Digital_IO,
dir_a: drivers.base.Digital_IO,
dir_b: drivers.base.Digital_IO,
state: State = .off,

pub fn begin(self: *Self) !void {
    // try self.enable.set_direction(.output);
    try self.enable.write(.low);
    // try self.dir_a.set_direction(.output);
    try self.dir_a.write(.low);
    // try self.dir_b.set_direction(.output);
    try self.dir_b.write(.low);
}
pub fn set(self: *Self, new_state: State) !void {
    if (self.state == new_state) {
        return;
    }
    switch (self.state) {
        .off => {},
        .dir_a => {
            try self.enable.write(.low);
            try self.dir_a.write(.low);
        },
        .dir_b => {
            try self.enable.write(.low);
            try self.dir_b.write(.low);
        },
    }
    switch (new_state) {
        .off => {},
        .dir_a => {
            try self.dir_a.write(.high);
            try self.enable.write(.high);
        },
        .dir_b => {
            try self.dir_b.write(.high);
            try self.enable.write(.high);
        },
    }
    self.state = new_state;
}
