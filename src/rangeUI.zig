const range = @import("range.zig");
const values = @import("tui/values.zig");
const IntValue = values.IntValue;
const Item = @import("tui/Tree.zig").Item;

pub fn RangeUI(comptime T: type, comptime R: type, comptime size: u8) type {
    return struct {
        const Self = @This();
        const RangeT = range.Range(T);
        const RangeR = range.Range(R);
        const Int = IntValue(T, R, size, 10);
        min: Int,
        max: Int,

        pub fn create(val: RangeT, min: RangeR, max: RangeR) Self {
            return .{
                .min = .{ .val = val.min, .range = min },
                .max = .{ .val = val.max, .range = max },
            };
        }

        pub fn ui(self: *Self) []const Item {
            return &.{
                .{ .label = " " }, // 1
                .{ .value = self.min.value() }, // 3
                .{ .label = ".. " }, // 3
                .{ .value = self.max.value() }, // 3
            };
        }
    };
}
