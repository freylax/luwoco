const PosControl = @import("PosControl.zig");
const DriveControl = @import("DriveControl.zig");
const values = @import("tui/values.zig");
const ClickButton = values.ClickButton;
const RoRefIntValue = values.RoRefIntValue;
const EnumRefValue = values.EnumRefValue;
const Item = @import("tui/Tree.zig").Item;
const uib = @import("ui_buttons.zig");

const Self = @This();

const ClickBt = ClickButton(PosControl);
const IntI8 = RoRefIntValue(i8, 3, 10);
const IntU16 = RoRefIntValue(u16, 3, 10);
const State = EnumRefValue(PosControl.State, [_][]const u8{ "fin", "pau", "mov", "cok" });

startBt: ClickBt,
pos_x: IntI8,
pos_y: IntI8,
steps: IntU16,
state: State,
timer_pos: IntU16,

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
        .state = .{ .ref = &pc.state },
        .timer_pos = .{ .ref = &pc.cook_timer_pos_s },
    };
}

pub fn ui(self: *Self) []const Item {
    return &.{
        .{ .value = self.state.value() }, // 3
        .{ .value = self.steps.value() }, // 3
        .{ .label = "x" }, // 1
        .{ .value = self.pos_x.value() }, // 3
        .{ .label = "y" }, // 1
        .{ .value = self.pos_y.value() }, // 3
        .{ .label = "\n" },
        .{ .value = self.timer_pos.value() }, // 3
        .{ .label = " =>" }, // 3
        .{ .value = self.startBt.value(.{ .db = uib.button2 }) }, // 3
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
