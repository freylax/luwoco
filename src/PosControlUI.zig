const PosControl = @import("PosControl.zig");
const DriveControl = @import("DriveControl.zig");
const values = @import("tui/values.zig");
const ClickButton = values.ClickButton;
const RoRefIntValue = values.RoRefIntValue;
const Item = @import("tui/Tree.zig").Item;
const uib = @import("ui_buttons.zig");

const Self = @This();

const ClickBt = ClickButton(PosControl);
const IntI8 = RoRefIntValue(i8, 3, 10);
const IntU16 = RoRefIntValue(u16, 3, 10);

startBt: ClickBt,
pos_x: IntI8,
pos_y: IntI8,
steps: IntU16,

pub fn create(pc: *PosControl, dx: *DriveControl, dy: *DriveControl) Self {
    return .{
        .startBt = .{
            .ref = pc,
            .enabled = startEnabled,
            .clicked = startClicked,
        },
        .pos_x = .{ .ref = &dx.pos.coord },
        .pos_y = .{ .ref = &dy.pos.coord },
        .steps = .{ .ref = &pc.steps },
    };
}

pub fn ui(self: *Self) []const Item {
    return &.{
        .{ .value = self.steps.value() }, // 3
        .{ .label = " x:" }, // 3
        .{ .value = self.pos_x.value() }, // 3
        .{ .label = " y:" }, // 3
        .{ .value = self.pos_y.value() }, // 3
        .{ .label = "\n" },
        // .{ .label = " =>" },
        .{ .value = self.startBt.value(.{ .db = uib.button2 }) },
    };
}

fn startEnabled(pc: *PosControl) bool {
    return switch (pc.state) {
        .finished => true,
        else => false,
    };
}

fn startClicked(pc: *PosControl) void {
    pc.start() catch {};
}
