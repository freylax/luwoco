const microzig = @import("microzig");
const time = microzig.drivers.time;
const std = @import("std");
const SampleButton = @import("SampleButton.zig");
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
    after_move,
    cooking,
    cooling,
};

drive_x_control: *DriveControl,
drive_y_control: *DriveControl,
cook_relais: *Relais,
cook_enable: *SampleButton,
cooking_time_dm: *u8, // cooking time in deci minutes
cooling_time_dm: *u8, // cooling time in deci minutes
after_move_time_ds: *u8,
work_area: Area,
skip_cooking: *bool,
x_dir: Dir = .forward,
y_dir: Dir = .forward,
axis: Axis = .xy,
x: i8 = 0,
y: i8 = 0,
steps: u16 = 0,
remaining_time_m: u16 = 0,
timer_us: u64 = 0,
timer_s: u16 = 0,
timer_update_us: u64 = 0,

state: State = .finished,

fn set_timer(self: *Self, sample_time: time.Absolute, duration_us: u64) void {
    self.timer_us = duration_us;
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
fn start_after_move(self: *Self, sample_time: time.Absolute) !void {
    self.state = .after_move;
    self.set_timer(sample_time, @as(u64, self.after_move_time_ds.*) *| 100_000);
}
fn start_cooking(self: *Self, sample_time: time.Absolute) !void {
    try self.cook_relais.set(switch (self.cook_enable.is_active) {
        true => .on,
        false => .off,
    });
    self.state = .cooking;
    self.set_timer(sample_time, @as(u64, self.cooking_time_dm.*) *| 6_000_000);
}
fn start_cooling(self: *Self, sample_time: time.Absolute) !void {
    try self.cook_relais.set(.off);
    self.state = .cooling;
    self.set_timer(sample_time, @as(u64, self.cooling_time_dm.*) *| 6_000_000);
}
fn next_step(self: *Self) !void {
    const dx = self.drive_x_control;
    const dy = self.drive_y_control;
    if (self.steps == 1) {
        self.state = .finished;
    } else {
        self.steps -= 1;
        self.update_remainig_time();
        switch (self.axis) {
            .x => {
                self.x += switch (self.x_dir) {
                    .forward => 1,
                    .backward => -1,
                };
                try dx.goto(self.x);
                self.state = .moving;
            },
            .y => {
                self.y += switch (self.y_dir) {
                    .forward => 1,
                    .backward => -1,
                };
                try dy.goto(self.y);
                self.state = .moving;
            },
            .xy => {},
        }
    }
}
fn move_done(self: *Self, sample_time: time.Absolute) !void {
    if (self.skip_cooking.*) {
        try self.next_step();
    } else {
        try self.start_after_move(sample_time);
    }
}
pub fn sample(self: *Self, sample_time: time.Absolute) !void {
    const dx = self.drive_x_control;
    const dy = self.drive_y_control;
    const wa = &self.work_area;
    switch (self.state) {
        .moving, .after_move, .paused_moving, .finished => {
            // prevent sampling of false signals if MW is active
            try dx.sample(sample_time);
            try dy.sample(sample_time);
        },
        .cooking, .cooling, .paused_cooking, .paused_cooling => {
            _ = try self.cook_enable.sample(sample_time);
        },
    }
    switch (self.state) {
        .moving => {
            switch (self.axis) {
                // initial pos
                .xy => if (dx.state == .stoped and dy.state == .stoped) {
                    self.axis = .x;
                    try self.move_done(sample_time);
                },
                .x => if (dx.state == .stoped) {
                    switch (self.x_dir) {
                        .forward => if (dx.pos.coord == wa.x.max.*) {
                            self.axis = .y;
                            self.x_dir = .backward;
                        },
                        .backward => if (dx.pos.coord == wa.x.min.*) {
                            self.axis = .y;
                            self.x_dir = .forward;
                        },
                    }
                    try self.move_done(sample_time);
                },
                .y => if (dy.state == .stoped) {
                    self.axis = .x;
                    try self.move_done(sample_time);
                },
            }
        },
        .after_move => {
            self.update_timer(sample_time);
            if (self.timer_us > 0) return;
            try self.start_cooking(sample_time);
        },
        .cooking => {
            switch (self.cook_enable.is_active) {
                true => {
                    switch (self.cook_relais.state) {
                        .on => {},
                        .off => {
                            // switch cook on
                            try self.cook_relais.set(.on);
                            //start counting now
                            self.timer_update_us = 0;
                        },
                    }
                },
                false => {
                    switch (self.cook_relais.state) {
                        .on => try self.cook_relais.set(.off), // switch cook off
                        .off => {},
                    }
                    // stop timer
                    self.timer_update_us = 0;
                },
            }
            self.update_timer(sample_time);
            if (self.timer_us > 0) return;
            try self.start_cooling(sample_time);
        },
        .cooling => {
            self.update_timer(sample_time);
            if (self.timer_us > 0) return;
            try self.next_step();
        },
        .paused_cooking => {},
        else => {},
    }
}
fn number_of_steps(self: *Self) u16 {
    const wa = &self.work_area;
    return @intCast((wa.x.max.* - wa.x.min.* + 1) * (wa.y.max.* - wa.y.min.* + 1));
}

pub fn start(self: *Self) !void {
    const dx = self.drive_x_control;
    const dy = self.drive_y_control;
    switch (self.state) {
        .finished => {
            const wa = &self.work_area;
            self.steps = self.number_of_steps();
            self.update_remainig_time();
            // find out which is the closest start position to the current position
            if (@abs(wa.x.max.* - dx.pos.coord) <= @abs(wa.x.min.* - dx.pos.coord)) {
                self.x_dir = .backward;
                self.x = wa.x.max.*;
            } else {
                self.x_dir = .forward;
                self.x = wa.x.min.*;
            }
            if (@abs(wa.y.max.* - dy.pos.coord) <= @abs(wa.y.min.* - dy.pos.coord)) {
                self.y_dir = .backward;
                self.y = wa.y.max.*;
            } else {
                self.y_dir = .forward;
                self.y = wa.y.min.*;
            }
            if (!dx.origin_ok) try dx.goToOrigin();
            if (!dy.origin_ok) try dy.goToOrigin();
            try dx.goto(self.x);
            try dy.goto(self.y);
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
            try self.cook_relais.set(switch (self.cook_enable.is_active) {
                true => .on,
                false => .off,
            });
            self.state = .cooking;
        },
        .paused_cooling => {
            self.state = .cooling;
        },
        else => {},
    }
}

fn update_remainig_time(self: *Self) void {
    const steps = if (self.steps != 0) self.steps else self.number_of_steps();
    self.remaining_time_m = (@as(u16, self.cooking_time_dm.*) +|
        @as(u16, self.cooling_time_dm.*)) *| steps / 10 +|
        @as(u16, @intCast(@as(u32, self.after_move_time_ds.*) *| steps / 600));
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
            try self.cook_relais.set(.off);
            self.state = .paused_cooking;
        },
        .cooling => {
            self.state = .paused_cooling;
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
    self.update_remainig_time();
}
