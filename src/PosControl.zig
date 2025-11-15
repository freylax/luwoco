const microzig = @import("microzig");
const time = microzig.drivers.time;

const std = @import("std");
const DriveControl = @import("DriveControl.zig");
const Area = @import("area.zig").Area(*const i8);

const Self = @This();

const Dir = enum { forward, backward };
const Axis = enum { x, y, xy };

pub const State = enum {
    finished,
    paused_moving,
    paused_cooking,
    moving,
    cooking,
};

drive_x_control: *DriveControl,
drive_y_control: *DriveControl,
cooking_time_xs: *u8, // cooking time in six seconds
work_area: Area,

x_dir: Dir = .forward,
y_dir: Dir = .forward,
axis: Axis = .xy,

steps: u16 = 0,
cook_timer_pos_us: u64 = 0,
cook_timer_pos_s: u16 = 0,
cook_timer_pos_update_us: u64 = 0,

state: State = .finished,

fn start_cooking(self: *Self, sample_time: time.Absolute) void {
    self.state = .cooking;
    self.cook_timer_pos_us = @as(u64, self.cooking_time_xs.*) *| 6_000_000;
    self.cook_timer_pos_update_us = sample_time.to_us();
    self.cook_timer_pos_s = @intCast((self.cook_timer_pos_us + 990_000) / 1_000_000);
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
                        self.start_cooking(sample_time);
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
                        self.start_cooking(sample_time);
                    }
                },
                .y => {
                    if (dy.state == .stoped) {
                        self.axis = .x;
                        self.start_cooking(sample_time);
                    }
                },
            }
        },
        .cooking => {
            if (self.cook_timer_pos_update_us == 0) {
                self.cook_timer_pos_update_us = sample_time.to_us();
            }
            self.cook_timer_pos_us -|= sample_time.to_us() -| self.cook_timer_pos_update_us;
            self.cook_timer_pos_s = @intCast((self.cook_timer_pos_us + 990_000) / 1_000_000);
            self.cook_timer_pos_update_us = sample_time.to_us();
            if (self.cook_timer_pos_us > 0) {
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
            self.cook_timer_pos_update_us = 0;
            self.state = .cooking;
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
