const microzig = @import("microzig");
const time = microzig.drivers.time;
const std = @import("std");
const Drive = @import("Drive.zig");
const SampleButton = @import("SampleButton.zig");

const Self = @This();

drive: *Drive,
pos: *SampleButton,
min: *SampleButton,
max: *SampleButton,

pub fn sample(self: *Self, sample_time: time.Absolute) !void {
    const pos = try self.pos.sample(sample_time);
    const min = try self.min.sample(sample_time);
    const max = try self.max.sample(sample_time);
    _ = pos;
    _ = min;
    _ = max;
}
