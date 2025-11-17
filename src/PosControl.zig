const microzig = @import("microzig");
const time = microzig.drivers.time;

const std = @import("std");
const DriveControl = @import("DriveControl.zig");
const Relais = @import("Relais.zig");
const Area = @import("area.zig").Area(*const i8);

const Self = @This();

const Dir = enum { forward, backward };
const Axis = enum { x, y, xy };

pub const State = enum {
    finished,
    paused_moving,
    paused_cooking,
    paused_cooling,
    moving,
    cooking,
    cooling,
};

drive_x_control: *DriveControl,
drive_y_control: *DriveControl,
switch_relais: *Relais,
cooking_time_dm: *u8, // cooking time in deci minutes
cooling_time_dm: *u8, // cooling time in deci minutes
work_area: Area,

x_dir: Dir = .forward,
y_dir: Dir = .forward,
axis: Axis = .xy,

steps: u16 = 0,
timer_us: u64 = 0,
timer_s: u16 = 0,
timer_update_us: u64 = 0,

state: State = .finished,

fn set_timer(self: *Self, sample_time: time.Absolute, duration_dm: u8) void {
    self.timer_us = @as(u64, duration_dm) *| 6_000_000;
    self.timer_update_us = sample_time.to_us();
    self.timer_s = @intCast((self.timer_us + 990_000) / 1_000_000);
}
fn update_timer(self: *Self, sample_time: time.Absolute) void {
    if (self.timer_update_us == 0) {
        self.timer_update_us = sample_time.to_us();
    }
    self.timer_us -|= sample_time.to_us() -| self.timer_update_us;
    self.timer_s = @intCast((self.timer_us + 990_000) / 1_000_000);
    self.timer_update_us = sample_time.to_us();
}
fn start_cooking(self: *Self, sample_time: time.Absolute) !void {
    try self.switch_relais.set(.on);
    self.state = .cooking;
    self.set_timer(sample_time, self.cooking_time_dm.*);
}

fn start_cooling(self: *Self, sample_time: time.Absolute) !void {
    try self.switch_relais.set(.off);
    self.state = .cooling;
    self.set_timer(sample_time, self.cooling_time_dm.*);
}

pub fn sample(self: *Self, sample_time: time.Absolute) !void {
    const dx = self.drive_x_control;
    const dy = self.drive_y_control;
    const wa = &self.work_area;
    try dx.sample(sample_time);
    try dy.sample(sample_time);
    switch (self.state) {
        .moving => {
            switch (self.axis) {
                .xy => {
                    // initial pos
                    if (dx.state == .stoped and dy.state == .stoped) {
                        self.axis = .x;
                        try self.start_cooking(sample_time);
                    }
                },
                .x => {
                    if (dx.state == .stoped) {
                        switch (self.x_dir) {
                            .forward => {
                                if (dx.pos.coord == wa.x.max.*) {
                                    self.axis = .y;
                                    self.x_dir = .backward;
                                }
                            },
                            .backward => {
                                if (dx.pos.coord == wa.x.min.*) {
                                    self.axis = .y;
                                    self.x_dir = .forward;
                                }
                            },
                        }
                        try self.start_cooking(sample_time);
                    }
                },
                .y => {
                    if (dy.state == .stoped) {
                        self.axis = .x;
                        try self.start_cooking(sample_time);
                    }
                },
            }
        },
        .cooking => {
            self.update_timer(sample_time);
            if (self.timer_us > 0) return;
            try self.start_cooling(sample_time);
        },
        .cooling => {
            self.update_timer(sample_time);
            if (self.timer_us > 0) {
                return;
            }
            if (self.steps == 1) {
                self.state = .finished;
            } else {
                self.steps -= 1;
                switch (self.axis) {
                    .x => {
                        switch (self.x_dir) {
                            .forward => {
                                try dx.stepForward();
                            },
                            .backward => {
                                try dx.stepBackward();
                            },
                        }
                        self.state = .moving;
                    },
                    .y => {
                        switch (self.y_dir) {
                            .forward => {
                                try dy.stepForward();
                            },
                            .backward => {
                                try dy.stepBackward();
                            },
                        }
                        self.state = .moving;
                    },
                    .xy => {},
                }
            }
        },
        else => {},
    }
}

pub fn start(self: *Self) !void {
    const dx = self.drive_x_control;
    const dy = self.drive_y_control;
    switch (self.state) {
        .finished => {
            const wa = &self.work_area;
            self.steps = @intCast((wa.x.max.* - wa.x.min.* + 1) * (wa.y.max.* - wa.y.min.* + 1));
            // find out which is the closest start position to the current position
            if (@abs(wa.x.max.* - dx.pos.coord) <= @abs(wa.x.min.* - dx.pos.coord)) {
                self.x_dir = .backward;
                try dx.goto(wa.x.max.*);
            } else {
                self.x_dir = .forward;
                try dx.goto(wa.x.min.*);
            }
            if (@abs(wa.y.max.* - dy.pos.coord) <= @abs(wa.y.min.* - dy.pos.coord)) {
                self.y_dir = .backward;
                try dy.goto(wa.y.max.*);
            } else {
                self.y_dir = .forward;
                try dy.goto(wa.y.min.*);
            }
            self.state = .moving;
            self.axis = .xy;
        },
        .paused_moving => {
            try dx.@"continue"();
            try dy.@"continue"();
            self.state = .moving;
        },
        .paused_cooking => {
            self.timer_update_us = 0;
            self.state = .cooking;
        },
        .paused_cooling => {
            self.state = .cooling;
        },
        else => {},
    }
}

pub fn pause(self: *Self) !void {
    const dx = self.drive_x_control;
    const dy = self.drive_y_control;
    switch (self.state) {
        .moving => {
            try dx.pause();
            try dy.pause();
            self.state = .paused_moving;
        },
        .cooking => {
            self.state = .paused_cooking;
        },
        else => {},
    }
}

pub fn reset(self: *Self) !void {
    switch (self.state) {
        .paused_moving, .paused_cooking, .paused_cooling => {
            self.steps = 0;
            self.state = .finished;
        },
        else => {},
    }
}
