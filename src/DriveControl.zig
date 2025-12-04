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
    go_to_origin,
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
ori_bt: *SampleButton,
lim_bt: *SampleButton,
min_coord: *i8,
max_coord: *i8,
max_segment_duration_ds: *u8,
avg_segment_duration: u64 = 0,
pos: Position = Position{},
dir: Direction = .unspec,
target_coord: i8 = 0,
state: State = .stoped,
segment_start: dtime.Absolute = .from_us(0),
dir_change: bool = false,
minimal_driving_time: dtime.Duration = .from_ms(500), // half a second

fn is_moving(self: *Self, sample_time: dtime.Absolute) !void {
    const p = &self.pos;
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
    const dt = sample_time.diff(self.segment_start).to_us();
    if (self.avg_segment_duration == 0) {
        self.avg_segment_duration = dt;
    } else {
        self.avg_segment_duration = (self.avg_segment_duration + dt) / 2;
    }
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
}

pub fn sample(self: *Self, sample_time: dtime.Absolute) !void {
    // const ori_ev = try self.ori_bt.sample(sample_time);
    const lim_ev = try self.lim_bt.sample(sample_time);
    const pos_ev = try self.pos_bt.sample(sample_time);
    switch (lim_ev) {
        .changed_to_active => {
            switch (self.pos_bt.is_active) {
                true => {
                    // origin position reached
                    if (self.state == .go_to_origin) {
                        try self.drive.set(.off);
                        self.pos.coord = 0;
                        self.target_coord = 0;
                        self.state = .stoped;
                        return;
                    }
                },
                false => {
                    // limit reached
                    try self.drive.set(.off);
                    self.state = .limited;
                    self.pos.dir = switch (self.ori_bt.is_active) {
                        true => .forward,
                        false => .backward,
                    };
                    return;
                },
            }
        },
        else => {},
    }
    const p = &self.pos;
    switch (pos_ev) {
        .changed_to_active => {
            switch (self.state) {
                .moving => try self.is_moving(sample_time),
                // a backslide of the trolley activates the switch again
                .stoped, .paused => p.dev = .exact,
                .limited, .time_exceeded, .go_to_origin => {},
            }
        },
        .changed_to_inactive => {
            // std.log.info("dc:change_to_inactive", .{});
            switch (self.state) {
                .moving, .go_to_origin => {
                    p.dir = self.dir;
                    p.dev = .between;
                },
                .stoped, .paused, .limited => p.dev = .between,
                .time_exceeded => {},
            }
        },
        .unchanged => switch (self.state) {
            .moving => {
                const dt = sample_time.diff(self.segment_start);
                const max_t = dtime.Duration.from_ms(@as(u64, self.max_segment_duration_ds.*) *| 100);
                // const max_t = self.avg_segment_duration + self.avg_segment_duration / 20; // 5% more as average
                if (max_t.to_us() != 0 and !dt.less_than(max_t)) {
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
        .moving, .go_to_origin, .time_exceeded => {},
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
        .moving, .go_to_origin, .time_exceeded => {},
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
        .moving, .go_to_origin, .time_exceeded => {},
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
        .moving, .go_to_origin => {
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

pub fn goToOrigin(self: *Self) !void {
    switch (self.state) {
        .stoped, .paused, .limited, .time_exceeded => {
            if (self.pos_bt.is_active and self.lim_bt.is_active) {
                // already at origin
                self.pos.coord = 0;
                self.target_coord = 0;
                self.state = .stoped;
            } else {
                switch (self.ori_bt.is_active) {
                    true => {
                        try self.drive.set(.dir_b);
                        self.dir = .backward;
                    },
                    false => {
                        try self.drive.set(.dir_a);
                        self.dir = .forward;
                    },
                }
                self.state = .go_to_origin;
            }
        },
        else => {},
    }
}

// pub fn calibrate(self: *Self) void {}

pub fn begin(self: *Self) !void {
    // if we use the device in simulation mode both are active!
    switch (self.lim_bt.is_active) {
        true => {
            switch (self.pos_bt.is_active) {
                true => {
                    // we are on the origin
                },
                false => {
                    // limit was reached
                    self.state = .limited;
                    self.pos.dir = switch (self.ori_bt.is_active) {
                        true => .forward,
                        false => .backward,
                    };
                },
            }
        },
        false => {},
    }
}
