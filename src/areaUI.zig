const range = @import("range.zig");
const area = @import("area.zig");
const rangeUI = @import("rangeUI.zig");
const Item = @import("tui/Tree.zig").Item;

pub fn AreaUI(comptime T: type, comptime R: type, comptime size: u8) type {
    return struct {
        const Self = @This();
        const RangeUI = rangeUI.RangeUI(T, R, size);
        const Area = area.Area(T);
        const Range = range.Range(R);

        x: RangeUI,
        y: RangeUI,

        pub fn create(val: Area, minx: Range, maxx: Range, miny: Range, maxy: Range) Self {
            return .{
                .x = RangeUI.create(val.x, minx, maxx),
                .y = RangeUI.create(val.y, miny, maxy),
            };
        }

        pub fn ui(self: *Self) []const Item {
            const I = Item;
            return &[_]I{.{ .label = "x: " }} ++ self.x.ui() ++ &[_]I{.{ .label = "\ny: " }} ++ self.y.ui();
        }
    };
}
