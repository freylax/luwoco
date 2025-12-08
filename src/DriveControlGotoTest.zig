const Range = @import("range.zig").Range(*const i8);
const DriveControl = @import("DriveControl.zig");

const Pos = enum { min, max };

dc: *DriveControl,
range: Range,

next_pos: Pos = .min,
