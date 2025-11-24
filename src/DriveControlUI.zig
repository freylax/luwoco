const DriveControl = @import("DriveControl.zig");
const values = @import("tui/values.zig");
const ClickButton = values.ClickButton;
const RoRefIntValue = values.RoRefIntValue;
const EnumRefValue = values.EnumRefValue;
const Item = @import("tui/Tree.zig").Item;
const uib = @import("ui_buttons.zig");

const Self = @This();

const ClickBt = ClickButton(DriveControl);
const Int = RoRefIntValue(i8, 3, 10);
const State = EnumRefValue(DriveControl.State, [_][]const u8{ "s", "l", "e", "m", "p" });
const Dir = EnumRefValue(DriveControl.Direction, [_][]const u8{ "u", "f", "b" });
const Dev = EnumRefValue(DriveControl.Deviation, [_][]const u8{ "x", "o" });

stopBt: ClickBt,
fwBt: ClickBt,
bwBt: ClickBt,
origBt: ClickBt,

pos_coord: Int,
pos_dir: Dir,
pos_dev: Dev,
target_coord: Int,
state: State,
dir: Dir,

pub fn create(dc: *DriveControl) Self {
    return .{
        .fwBt = .{
            .ref = dc,
            .enabled = stepForwardEnabled,
            .clicked = stepForwardClicked,
        },
        .bwBt = .{
            .ref = dc,
            .enabled = stepBackwardEnabled,
            .clicked = stepBackwardClicked,
        },
        .stopBt = .{
            .ref = dc,
            .enabled = stopEnabled,
            .clicked = stopClicked,
        },
        .origBt = .{
            .ref = dc,
            .enabled = origEnabled,
            .clicked = origClicked,
        },
        .pos_coord = .{ .ref = &dc.pos.coord },
        .pos_dir = .{ .ref = &dc.pos.dir },
        .pos_dev = .{ .ref = &dc.pos.dev },
        .target_coord = .{ .ref = &dc.target_coord },
        .state = .{ .ref = &dc.state },
        .dir = .{ .ref = &dc.dir },
    };
}

pub fn ui(self: *Self) []const Item {
    return &.{
        .{ .value = self.state.value() }, // 1
        .{ .value = self.dir.value() }, // 1
        // .{ .label = "  " },
        .{ .value = self.pos_coord.value() }, // 3
        .{ .value = self.pos_dir.value() }, // 1
        .{ .value = self.pos_dev.value() }, // 1
        .{ .label = " =>" }, // 3
        .{ .value = self.target_coord.value() }, // 3
        .{ .label = "\n" },
        .{ .label = "#" },
        .{ .value = self.stopBt.value(.{ .db = uib.button1 }) },
        .{ .label = "-" },
        .{ .value = self.bwBt.value(.{ .db = uib.button2 }) },
        .{ .label = "+" },
        .{ .value = self.fwBt.value(.{ .db = uib.button3 }) },
        .{ .label = "o" },
        .{ .value = self.origBt.value(.{ .db = uib.button4 }) },
    };
}

fn stepForwardEnabled(dc: *DriveControl) bool {
    return switch (dc.state) {
        .stoped => true,
        .limited => (dc.pos.dir == .backward),
        else => false,
    };
}

fn stepForwardClicked(dc: *DriveControl) void {
    dc.stepForward() catch {};
}

fn stepBackwardEnabled(dc: *DriveControl) bool {
    return switch (dc.state) {
        .stoped => true,
        .limited => (dc.pos.dir == .forward),
        else => false,
    };
}

fn stepBackwardClicked(dc: *DriveControl) void {
    dc.stepBackward() catch {};
}

fn stopEnabled(dc: *DriveControl) bool {
    return switch (dc.state) {
        .moving => true,
        else => false,
    };
}

fn stopClicked(dc: *DriveControl) void {
    dc.stop() catch {};
}

fn origEnabled(dc: *DriveControl) bool {
    return switch (dc.state) {
        .stoped, .paused, .limited, .time_exceeded => true,
        else => false,
    };
}

fn origClicked(dc: *DriveControl) void {
    dc.setOrigin();
}
