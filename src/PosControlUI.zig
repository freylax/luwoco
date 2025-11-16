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
const State = EnumRefValue(PosControl.State, [_][]const u8{ "fin", "pam", "pac", "mov", "cok" });

startBt: ClickBt,
pauseBt: ClickBt,
resetBt: ClickBt,
pos_x: IntI8,
pos_y: IntI8,
steps: IntU16,
state: State,
timer_pos: IntU16,

pub fn create(pc: *PosControl, dx: *DriveControl, dy: *DriveControl) Self {
    return .{
        .startBt = .{ .ref = pc, .enabled = startEnabled, .clicked = startClicked },
        .pauseBt = .{ .ref = pc, .enabled = pauseEnabled, .clicked = pauseClicked },
        .resetBt = .{ .ref = pc, .enabled = resetEnabled, .clicked = resetClicked },
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
        .{ .label = " >" }, // 2
        .{ .value = self.startBt.value(.{ .db = uib.button2 }) }, // 3
        .{ .label = "=" }, // 1
        .{ .value = self.pauseBt.value(.{ .db = uib.button3 }) }, // 3
        .{ .label = "R" }, // 1
        .{ .value = self.resetBt.value(.{ .db = uib.button4 }) }, // 3
    };
}

fn startEnabled(pc: *PosControl) bool {
    return switch (pc.state) {
        .finished, .paused_moving, .paused_cooking => true,
        else => false,
    };
}

fn startClicked(pc: *PosControl) void {
    pc.start() catch {};
}
fn pauseEnabled(pc: *PosControl) bool {
    return switch (pc.state) {
        .moving, .cooking => true,
        else => false,
    };
}
fn pauseClicked(pc: *PosControl) void {
    pc.pause() catch {};
}
fn resetEnabled(pc: *PosControl) bool {
    return switch (pc.state) {
        .paused_moving, .paused_cooking => true,
        else => false,
    };
}
fn resetClicked(pc: *PosControl) void {
    pc.reset() catch {};
}
