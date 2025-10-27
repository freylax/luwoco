const microzig = @import("microzig");
const std = @import("std");
const drivers = microzig.drivers;
const Digital_IO = drivers.base.Digital_IO;
const Self = @This();

pub const State = enum { off, dir_a, dir_b };
enable: Digital_IO,
dir_a: Digital_IO,
dir_b: Digital_IO,
state: State = .off,
use_simulator: *const bool,
sim_enable: *Digital_IO.State,
sim_dir_a: *Digital_IO.State,
sim_dir_b: *Digital_IO.State,

fn set_enable(self: *Self, s: Digital_IO.State) !void {
    if (self.use_simulator.*) {
        self.sim_enable.* = s;
    } else {
        try self.enable.write(s);
    }
}

fn set_dir_a(self: *Self, s: Digital_IO.State) !void {
    if (self.use_simulator.*) {
        self.sim_dir_a.* = s;
    } else {
        try self.dir_a.write(s);
    }
}

fn set_dir_b(self: *Self, s: Digital_IO.State) !void {
    if (self.use_simulator.*) {
        self.sim_dir_b.* = s;
    } else {
        try self.dir_b.write(s);
    }
}

pub fn begin(self: *Self) !void {
    try self.set_enable(.low);
    try self.set_dir_a(.low);
    try self.set_dir_b(.low);
}
pub fn set(self: *Self, new_state: State) !void {
    if (self.state == new_state) {
        return;
    }
    switch (self.state) {
        .off => {},
        .dir_a => {
            try self.set_enable(.low);
            try self.set_dir_a(.low);
        },
        .dir_b => {
            try self.set_enable(.low);
            try self.set_dir_b(.low);
        },
    }
    switch (new_state) {
        .off => {},
        .dir_a => {
            try self.set_dir_a(.high);
            try self.set_enable(.high);
        },
        .dir_b => {
            try self.set_dir_b(.high);
            try self.set_enable(.high);
        },
    }
    self.state = new_state;
}
