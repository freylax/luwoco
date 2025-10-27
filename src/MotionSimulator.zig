const microzig = @import("microzig");
const std = @import("std");
const drivers = microzig.drivers;
const Digital_IO = drivers.base.Digital_IO;
const IOState = Digital_IO.State;
const time = drivers.time;

const Self = @This();

min: IOState = .low,
max: IOState = .low,
pos: IOState = .low,
enable: IOState = .low,
dir_a: IOState = .low,
dir_b: IOState = .low,

run: bool = false,

pub fn sample(self: *Self, sample_time: time.Absolute) void {
    _ = self;
    _ = sample_time;
}
