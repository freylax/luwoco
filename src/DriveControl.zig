const microzig = @import("microzig");
const time = microzig.drivers.time;
const std = @import("std");
const Drive = @import("Drive.zig");
const SampleButton = @import("SampleButton.zig");

const Self = @This();

pub const State = enum {
    stoped,
    limited,
    moving,
};

pub const Deviation = enum(u2) { exact, small, coarse };
pub const Direction = enum(u2) { unspec, forward, backward };

pub const Position = struct {
    coord: i8 = 0,
    dev: Deviation = .exact,
    dir: Direction = .unspec,
};

drive: *Drive,
pos_bt: *SampleButton,
min_bt: *SampleButton,
max_bt: *SampleButton,
min_coord: *i8,
max_coord: *i8,
pos: Position = Position{},
dir: Direction = .unspec,
target_coord: i8 = 0,
state: State = .stoped,

pub fn sample(self: *Self, sample_time: time.Absolute) !void {
    const min_ev = try self.min_bt.sample(sample_time);
    const max_ev = try self.max_bt.sample(sample_time);
    const pos_ev = try self.pos_bt.sample(sample_time);
    if (min_ev == .changed_to_active) {
        try self.drive.set(.off);
        self.state = .limited;
        self.pos.dir = .backward;
        return;
    }
    if (max_ev == .changed_to_active) {
        try self.drive.set(.off);
        self.state = .limited;
        self.pos.dir = .forward;
        return;
    }
    const p = &self.pos;
    switch (pos_ev) {
        .changed_to_active => {
            switch (self.state) {
                .moving => {
                    switch (p.dir) {
                        .forward => {
                            switch (self.dir) {
                                .forward => {
                                    p.coord += 1;
                                },
                                .backward => {
                                    p.dir = .backward;
                                },
                                .unspec => {},
                            }
                        },
                        .backward => {
                            switch (self.dir) {
                                .forward => {
                                    p.dir = .forward;
                                },
                                .backward => {
                                    self.pos.coord -= 1;
                                },
                                .unspec => {},
                            }
                        },
                        .unspec => {
                            switch (self.dir) {
                                .forward => {
                                    p.dir = .forward;
                                },
                                .backward => {
                                    p.dir = .backward;
                                },
                                .unspec => {},
                            }
                        },
                    }
                    p.dev = .exact;
                    if (p.coord == self.min_coord.* or p.coord == self.max_coord.*) {
                        try self.drive.set(.off);
                        self.state = .limited;
                    }
                    if (p.coord == self.target_coord) {
                        // stop the drive
                        try self.drive.set(.off);
                        self.state = .stoped;
                    }
                },
                .stoped => {
                    // a backslide of the switch
                    p.dev = .exact;
                },
                .limited => {},
            }
        },
        .changed_to_inactive => {
            switch (self.state) {
                .moving => {
                    p.dir = self.dir;
                    p.dev = .coarse;
                },
                .stoped, .limited => {
                    p.dev = .small;
                },
            }
        },
        .unchanged => {},
    }
}
pub fn stepForward(self: *Self) !void {
    switch (self.state) {
        .stoped => {
            self.dir = .forward;
            self.target_coord = self.pos.coord + 1;
            try self.drive.set(.dir_a);
            self.state = .moving;
        },
        .limited => {
            switch (self.pos.dir) {
                .backward => {
                    self.dir = .forward;
                    self.target_coord = self.pos.coord + 1;
                    try self.drive.set(.dir_a);
                    self.state = .moving;
                },
                else => {},
            }
        },
        .moving => {},
    }
}

pub fn stepBackward(self: *Self) !void {
    switch (self.state) {
        .stoped => {
            self.dir = .backward;
            self.target_coord = self.pos.coord - 1;
            try self.drive.set(.dir_b);
            self.state = .moving;
        },
        .limited => {
            switch (self.pos.dir) {
                .forward => {
                    self.dir = .backward;
                    self.target_coord = self.pos.coord - 1;
                    try self.drive.set(.dir_b);
                    self.state = .moving;
                },
                else => {},
            }
        },
        .moving => {},
    }
}

pub fn stop(self: *Self) !void {
    try self.drive.set(.off);
    switch (self.state) {
        .moving => {
            try self.drive.set(.off);
            self.state = .stoped;
        },
        else => {},
    }
}

pub fn setOrigin(self: *Self) void {
    switch (self.state) {
        .stoped => {
            self.pos.coord = 0;
            self.target_coord = 0;
        },
        else => {},
    }
}

pub fn begin(self: *Self) !void {
    if (self.max_bt.is_active) {
        self.state = .limited;
        self.pos.dir = .forward;
    } else if (self.min_bt.is_active) {
        self.state = .limited;
        self.pos.dir = .backward;
    }
}
