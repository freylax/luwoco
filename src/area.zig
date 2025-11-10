const Range = @import("range.zig").Range;

pub fn Area(comptime T: type) type {
    return struct {
        x: Range(T),
        y: Range(T),
    };
}
