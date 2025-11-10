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
    paused,
    moving,
    waiting,
};

drive_x_control: *DriveControl,
drive_y_control: *DriveControl,
waiting_time_xs: *u8, // waiting time in six seconds
work_area: Area,

x_dir: Dir = .forward,
y_dir: Dir = .forward,
axis: Axis = .xy,

steps: u16 = 0,

state: State = .finished,

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
                        self.state = .waiting;
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
                        self.state = .waiting;
                    }
                },
                .y => {
                    if (dy.state == .stoped) {
                        self.axis = .x;
                        self.state = .waiting;
                    }
                },
            }
        },
        .waiting => {
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
        },
        else => {},
    }
}
