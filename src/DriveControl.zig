const microzig = @import("microzig");
const time = microzig.drivers.time;
const std = @import("std");
const Drive = @import("Drive.zig");
const SampleButton = @import("SampleButton.zig");

const Self = @This();

const State = enum {
    idle,
    stoped,
    stoped_by_min,
    stoped_by_max,
    driving,
};

drive: *Drive,
pos_bt: *SampleButton,
min_bt: *SampleButton,
max_bt: *SampleButton,
last_pos: i8 = 0,
target_pos: i8 = 0,
state: State = .idle,

pub fn sample(self: *Self, sample_time: time.Absolute) !void {
    const pos_ev = try self.pos_bt.sample(sample_time);
    const min_ev = try self.min_bt.sample(sample_time);
    const max_ev = try self.max_bt.sample(sample_time);
    if (self.state == .driving) {
        if (min_ev == .changed_to_active) {
            try self.drive.set(.off);
            self.state = .stoped_by_min;
        } else if (max_ev == .changed_to_active) {
            try self.drive.set(.off);
            self.state = .stoped_by_max;
        } else if (pos_ev == .changed_to_active) {
            if (self.last_pos < self.target_pos) {
                self.last_pos += 1;
            } else if (self.last_pos > self.target_pos) {
                self.last_pos -= 1;
            }
            if (self.last_pos == self.target_pos) {
                // stop the drive
                try self.drive.set(.off);
                self.state = .idle;
            }
        }
    }
}

pub fn stepForward(self: *Self) !void {
    switch (self.state) {
        .idle => {
            self.target_pos = self.last_pos + 1;
            try self.drive.set(.dir_a);
            self.state = .driving;
        },
        .stoped => {
            if (self.last_pos < self.target_pos) {
                // continue direction
                self.target_pos = self.last_pos + 1;
                try self.drive.set(.dir_a);
                self.state = .driving;
            } else if (self.last_pos > self.target_pos) {
                // change direction after stop
                self.target_pos = self.last_pos;
                self.last_pos -= 1;
                try self.drive.set(.dir_a);
                self.state = .driving;
            }
        },
        .stoped_by_min => {
            self.target_pos = self.last_pos;
            self.last_pos -= 1;
            try self.drive.set(.dir_a);
            self.state = .driving;
        },
        else => {},
    }
}

pub fn stepBackward(self: *Self) !void {
    switch (self.state) {
        .idle => {
            self.target_pos = self.last_pos - 1;
            try self.drive.set(.dir_b);
            self.state = .driving;
        },
        .stoped => {
            if (self.last_pos > self.target_pos) {
                // continue direction
                self.target_pos = self.last_pos - 1;
                try self.drive.set(.dir_b);
                self.state = .driving;
            } else if (self.last_pos < self.target_pos) {
                // change direction after stop
                self.target_pos = self.last_pos;
                self.last_pos += 1;
                try self.drive.set(.dir_b);
                self.state = .driving;
            }
        },
        .stoped_by_max => {
            self.target_pos = self.last_pos;
            self.last_pos += 1;
            try self.drive.set(.dir_b);
            self.state = .driving;
        },
        else => {},
    }
}

pub fn stop(self: *Self) !void {
    try self.drive.set(.off);
    switch (self.state) {
        .driving => {
            self.state = .stoped;
        },
        else => {},
    }
}

pub fn begin(self: *Self) !void {
    if (self.max_bt.is_active) {
        self.state = .stoped_by_max;
    } else if (self.min_bt.is_active) {
        self.state = .stoped_by_min;
    }
}
