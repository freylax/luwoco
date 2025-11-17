const microzig = @import("microzig");
const std = @import("std");
const drivers = microzig.drivers;
const Digital_IO = drivers.base.Digital_IO;
const IOState = Digital_IO.State;
const time = drivers.time;

const Self = @This();

pub const State = enum { stoped, moving };

pub const Deviation = enum(u2) { exact, coarse };
pub const Direction = enum(u2) { unspec, forward, backward };

pub const Position = struct {
    coord: i8 = 0,
    dev: Deviation = .exact,
    dir: Direction = .unspec,
};

switching_time_cs: *u8,
driving_time_s: *u8,
active: IOState,
inactive: IOState,
min_pin: IOState,
max_pin: IOState,
pos_pin: IOState,
enable_pin: IOState = .low,
dir_a_pin: IOState = .low,
dir_b_pin: IOState = .low,

pos: Position = Position{},
state: State = .stoped,
last_change: time.Absolute = .from_us(0),

pub fn sample(self: *Self, sample_time: time.Absolute) void {
    switch (self.state) {
        .stoped => {
            switch (self.enable_pin) {
                .high => {
                    // start drive
                    const dir: Direction = if (self.dir_a_pin == .high) .forward else if (self.dir_b_pin == .high) .backward else .unspec;
                    switch (self.pos.dev) {
                        .exact => {}, // start from exact position
                        .coarse => { // start from inbetween
                            if (dir != self.pos.dir) {
                                // correct coord if we have a direction change
                                self.pos.coord += switch (dir) {
                                    .forward => -1,
                                    .backward => 1,
                                    .unspec => 0,
                                };
                            }
                        },
                    }
                    self.state = .moving;
                    self.pos.dir = dir;
                },
                .low => {},
            }
        },
        .moving => {
            switch (self.enable_pin) {
                .high => {
                    // moving
                    const dt = sample_time.diff(self.last_change);
                    switch (self.pos.dev) {
                        .exact => {
                            const switching_time: time.Duration = .from_ms(@as(u64, self.switching_time_cs.*) *| 10);
                            if (switching_time.less_than(dt)) {
                                self.pos.dev = .coarse;
                                self.pos_pin = self.inactive;
                                self.last_change = sample_time;
                            }
                        },
                        .coarse => {
                            const driving_time: time.Duration = .from_ms(@as(u64, self.driving_time_s.*) *| 1000);
                            if (driving_time.less_than(dt)) {
                                // we arrive at the next coord
                                self.pos.dev = .exact;
                                self.pos_pin = self.active;
                                self.last_change = sample_time;
                                if (self.dir_a_pin == .high) {
                                    self.pos.coord += 1;
                                }
                                if (self.dir_a_pin == .high) {
                                    self.pos.coord -= 1;
                                }
                            }
                        },
                    }
                },
                .low => {
                    self.state = .stoped;
                },
            }
        },
    }
}
