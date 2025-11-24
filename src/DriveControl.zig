const microzig = @import("microzig");
const dtime = microzig.drivers.time;
const time = microzig.hal.time;
const std = @import("std");
const Drive = @import("Drive.zig");
const SampleButton = @import("SampleButton.zig");

const Self = @This();

pub const State = enum {
    stoped,
    limited,
    time_exceeded,
    moving,
    paused,
};

pub const Deviation = enum(u2) { exact, between };
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
max_segment_duration_ds: *u8,
pos: Position = Position{},
dir: Direction = .unspec,
target_coord: i8 = 0,
state: State = .stoped,
segment_start: dtime.Absolute = .from_us(0),
dir_change: bool = false,
minimal_driving_time: dtime.Duration = .from_ms(500), // half a second

pub fn sample(self: *Self, sample_time: dtime.Absolute) !void {
    const min_ev = try self.min_bt.sample(sample_time);
    const max_ev = try self.max_bt.sample(sample_time);
    const pos_ev = try self.pos_bt.sample(sample_time);
    if (min_ev == .changed_to_active) {
        // std.log.info("dc:sample min_ev changed to active", .{});
        try self.drive.set(.off);
        self.state = .limited;
        self.pos.dir = .backward;
        return;
    }
    if (max_ev == .changed_to_active) {
        // std.log.info("dc:sample max_ev changed to active", .{});
        try self.drive.set(.off);
        self.state = .limited;
        self.pos.dir = .forward;
        return;
    }
    const p = &self.pos;
    switch (pos_ev) {
        .changed_to_active => {
            // std.log.info("dc:change_to_active1, coord={d},min={d},max={d}", .{ p.coord, self.min_coord.*, self.max_coord.* });
            switch (self.state) {
                .moving => {
                    switch (p.dir) {
                        // last position was in forward direction
                        .forward => {
                            switch (self.dir) {
                                .forward => if (!(self.dir_change and sample_time.diff(self.segment_start).less_than(self.minimal_driving_time))) {
                                    p.coord += 1;
                                },
                                .backward => {
                                    p.dir = .backward;
                                    switch (p.dev) {
                                        .exact => p.coord -= 1,
                                        .between => {},
                                    }
                                },
                                .unspec => {},
                            }
                        },
                        // last position was in backward direction
                        .backward => {
                            switch (self.dir) {
                                .forward => {
                                    p.dir = .forward;
                                    switch (p.dev) {
                                        .exact => p.coord += 1,
                                        .between => {},
                                    }
                                },
                                .backward => if (!(self.dir_change and sample_time.diff(self.segment_start).less_than(self.minimal_driving_time))) {
                                    p.coord -= 1;
                                },
                                .unspec => {},
                            }
                        },
                        .unspec => p.dir = self.dir,
                    }
                    p.dev = .exact;
                    self.segment_start = sample_time;
                    self.dir_change = false;
                    // std.log.info("dc:change_to_active2, coord={d},min={d},max={d}", .{ p.coord, self.min_coord.*, self.max_coord.* });
                    if (p.coord == self.target_coord) {
                        // stop the drive
                        try self.drive.set(.off);
                        self.state = .stoped;
                    } else if (p.coord == self.min_coord.* or p.coord == self.max_coord.*) {
                        try self.drive.set(.off);
                        self.state = .limited;
                    }
                },
                // a backslide of the trolley activates the switch again
                .stoped, .paused => p.dev = .exact,
                .limited, .time_exceeded => {},
            }
        },
        .changed_to_inactive => {
            // std.log.info("dc:change_to_inactive", .{});
            switch (self.state) {
                .moving => {
                    p.dir = self.dir;
                    p.dev = .between;
                },
                .stoped, .paused, .limited => p.dev = .between,
                .time_exceeded => {},
            }
        },
        .unchanged => switch (self.state) {
            .moving => {
                const max_t = dtime.Duration.from_ms(@as(u64, self.max_segment_duration_ds.*) *| 100);
                if (!sample_time.diff(self.segment_start).less_than(max_t)) {
                    try self.drive.set(.off);
                    self.state = .time_exceeded;
                }
            },
            else => {},
        },
    }
}
pub fn stepForward(self: *Self) !void {
    switch (self.state) {
        .stoped, .paused => {
            self.target_coord = self.pos.coord + 1;
            try self.start_drive(.forward);
        },
        .limited => {
            switch (self.pos.dir) {
                .backward => {
                    self.target_coord = self.pos.coord + 1;
                    try self.start_drive(.forward);
                },
                else => {},
            }
        },
        .moving, .time_exceeded => {},
    }
}

pub fn stepBackward(self: *Self) !void {
    switch (self.state) {
        .stoped, .paused => {
            self.target_coord = self.pos.coord - 1;
            try self.start_drive(.backward);
        },
        .limited => {
            switch (self.pos.dir) {
                .forward => {
                    self.target_coord = self.pos.coord - 1;
                    try self.start_drive(.backward);
                },
                else => {},
            }
        },
        .moving, .time_exceeded => {},
    }
}

pub fn goto(self: *Self, coord: i8) !void {
    switch (self.state) {
        .paused, .stoped, .limited => {
            const inrange = coord >= self.min_coord.* and coord <= self.max_coord.*;
            if (inrange and coord > self.pos.coord and (self.state != .limited or self.dir == .backward)) {
                self.target_coord = coord;
                try self.start_drive(.forward);
            } else if (inrange and coord < self.pos.coord and (self.state != .limited or self.dir == .forward)) {
                self.target_coord = coord;
                try self.start_drive(.backward);
            }
        },
        .moving, .time_exceeded => {},
    }
}

fn start_drive(self: *Self, dir: Direction) !void {
    switch (dir) {
        .forward, .backward => {
            try self.drive.set(if (dir == .forward) .dir_a else .dir_b);
            self.segment_start = time.get_time_since_boot();
            self.dir_change = self.dir != dir;
            self.dir = dir;
            self.state = .moving;
        },
        .unspec => {},
    }
}

pub fn stop(self: *Self) !void {
    switch (self.state) {
        .moving => {
            try self.drive.set(.off);
            self.state = .stoped;
        },
        else => {},
    }
}

pub fn pause(self: *Self) !void {
    switch (self.state) {
        .moving => {
            try self.drive.set(.off);
            self.state = .paused;
        },
        else => {},
    }
}

pub fn @"continue"(self: *Self) !void {
    switch (self.state) {
        .paused => try self.start_drive(self.dir),
        else => {},
    }
}

pub fn setOrigin(self: *Self) void {
    switch (self.state) {
        .stoped, .paused, .limited, .time_exceeded => {
            self.pos.coord = 0;
            self.target_coord = 0;
            self.state = .stoped;
        },
        else => {},
    }
}

pub fn begin(self: *Self) !void {
    // if we use the device in simulation mode both are active!
    if (self.max_bt.is_active and !self.min_bt.is_active) {
        self.state = .limited;
        self.pos.dir = .forward;
    } else if (self.min_bt.is_active and !self.max_bt.is_active) {
        self.state = .limited;
        self.pos.dir = .backward;
    }
}
