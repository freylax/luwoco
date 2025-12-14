const microzig = @import("microzig");
const dtime = microzig.drivers.time;
const time = microzig.hal.time;
const system_timer = microzig.hal.system_timer;
const timer0 = system_timer.num(0);
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
lim_check_delay_cs: *u8,
pos: Position = Position{},
dir: Direction = .unspec,
target_coord: i8 = 0,
goto_after_origin: ?i8 = null,
state: State = .stoped,
segment_start: dtime.Absolute = .from_us(0),
dir_change: bool = false,
minimal_driving_time: dtime.Duration = .from_ms(500), // half a second
origin_ok: bool = false, // true if origin was detected and initialized

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
    const ori_ev = try self.ori_bt.sample(sample_time);
    const lim_ev = try self.lim_bt.sample(sample_time);
    const pos_ev = try self.pos_bt.sample(sample_time);
    const p = &self.pos;
    switch (lim_ev) {
        .changed_to_active => {
            switch (self.pos_bt.is_active) {
                true => {
                    // origin position reached
                    switch (self.state) {
                        .go_to_origin => {
                            try self.drive.set(.off);
                            try self.setOrigin();
                            return;
                        },
                        .stoped, .paused => {
                            p.coord = 0;
                            p.dev = .exact;
                            self.origin_ok = true;
                        },
                        .moving => {
                            p.coord = 0;
                            p.dev = .exact;
                            self.origin_ok = true;
                            if ((p.dir == .forward and p.coord >= self.target_coord) or (p.dir == .backward and p.coord <= self.target_coord)) {
                                // stop the drive
                                try self.drive.set(.off);
                                self.state = .stoped;
                            }
                        },
                        else => {},
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
    switch (ori_ev) {
        .changed_to_active, .changed_to_inactive => {
            switch (self.state) {
                .go_to_origin => {
                    // origin position reached
                    try self.drive.set(.off);
                    try self.setOrigin();
                    return;
                },
                else => {},
            }
        },
        .unchanged => {},
    }
    switch (pos_ev) {
        .changed_to_active => {
            switch (self.state) {
                .moving => try self.is_moving(sample_time),
                .go_to_origin => {
                    // we stop the drive and look then forward if we get a
                    // lim_bt activated after this
                    // stoping is needed because otherwise we get the stop signal too late
                    try self.drive.set(.off);
                    p.dev = .exact;
                    self.segment_start = sample_time;
                    const dt_us = @as(u32, @max(self.lim_check_delay_cs.*, 1)) *| 10_000;
                    timer0.clear_interrupt(.alarm0);
                    timer0.schedule_alarm(.alarm0, timer0.read_low() +% dt_us);
                },
                // a backslide of the trolley activates the switch again
                .stoped, .paused => p.dev = .exact,
                .limited, .time_exceeded => {},
            }
        },
        .changed_to_inactive => {
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
            .moving, .go_to_origin => {
                if (self.state == .go_to_origin and self.drive.state == .off) {
                    // we arrive here on behave of our sceduled alarm
                    if (!self.lim_bt.is_active) {
                        // we are not at the origin right now, start drive again
                        switch (self.dir) {
                            .forward => try self.drive.set(.dir_a),
                            .backward => try self.drive.set(.dir_b),
                            .unspec => {},
                        }
                    } else {
                        // this might be a duplicate to lim_bt changed to active switch,
                        // but for sure
                        try self.setOrigin();
                    }
                } else {
                    const dt = sample_time.diff(self.segment_start);
                    const max_t = dtime.Duration.from_ms(@as(u64, self.max_segment_duration_ds.*) *| 100);
                    if (max_t.to_us() != 0 and !dt.less_than(max_t)) {
                        try self.drive.set(.off);
                        self.state = .time_exceeded;
                    }
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
    if (!self.origin_ok) {
        try self.goToOrigin();
        self.goto_after_origin = coord;
    } else {
        switch (self.state) {
            .paused, .stoped, .limited => try self.goto_intern(coord),
            .moving, .go_to_origin, .time_exceeded => {},
        }
    }
}

fn goto_intern(self: *Self, coord: i8) !void {
    const inrange = coord >= self.min_coord.* and coord <= self.max_coord.*;
    if (inrange and coord > self.pos.coord and (self.state != .limited or self.dir == .backward)) {
        self.target_coord = coord;
        try self.start_drive(.forward);
    } else if (inrange and coord < self.pos.coord and (self.state != .limited or self.dir == .forward)) {
        self.target_coord = coord;
        try self.start_drive(.backward);
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

fn setOrigin(self: *Self) !void {
    self.pos.coord = 0;
    self.pos.dev = .exact;
    self.target_coord = 0;
    self.origin_ok = true;
    if (self.goto_after_origin) |coord| {
        self.goto_after_origin = null;
        try self.goto_intern(coord);
    } else {
        self.state = .stoped;
    }
}

pub fn goToOrigin(self: *Self) !void {
    switch (self.state) {
        .stoped, .paused, .limited, .time_exceeded => {
            if (self.pos_bt.is_active and self.lim_bt.is_active) {
                // already at origin
                try self.setOrigin();
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
                self.segment_start = time.get_time_since_boot();
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
                    try self.setOrigin();
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
