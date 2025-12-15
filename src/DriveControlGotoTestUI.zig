const DriveControl = @import("DriveControl.zig");
const DriveControlGotoTest = @import("DriveControlGotoTest.zig");
const values = @import("tui/values.zig");
const ClickButton = values.ClickButton;
const RoRefIntValue = values.RoRefIntValue;
const EnumRefValue = values.EnumRefValue;
const Item = @import("tui/Tree.zig").Item;
const uib = @import("ui_buttons.zig");

const Self = @This();

const ClickBt = ClickButton(DriveControlGotoTest);
const Int = RoRefIntValue(i8, 3, 10);
const State = EnumRefValue(DriveControl.State, [_][]const u8{ "s", "l", "e", "m", "p", "o" });
const Dir = EnumRefValue(DriveControl.Direction, [_][]const u8{ "u", "f", "b" });
const Dev = EnumRefValue(DriveControl.Deviation, [_][]const u8{ "x", "o" });

stopBt: ClickBt,
startBt: ClickBt,
origBt: ClickBt,

pos_coord: Int,
pos_dir: Dir,
pos_dev: Dev,
target_coord: Int,
state: State,
dir: Dir,

pub fn create(dcgt: *DriveControlGotoTest, dc: *DriveControl) Self {
    return .{
        .startBt = .{
            .ref = dcgt,
            .enabled = startEnabled,
            .clicked = startClicked,
        },
        .stopBt = .{
            .ref = dcgt,
            .enabled = stopEnabled,
            .clicked = stopClicked,
        },
        .origBt = .{
            .ref = dcgt,
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
        .{ .value = self.state.value(.ro) }, // 1
        .{ .value = self.dir.value(.ro) }, // 1
        // .{ .label = "  " },
        .{ .value = self.pos_coord.value() }, // 3
        .{ .value = self.pos_dir.value(.ro) }, // 1
        .{ .value = self.pos_dev.value(.ro) }, // 1
        .{ .label = " =>" }, // 3
        .{ .value = self.target_coord.value() }, // 3
        .{ .label = "\n" },
        .{ .label = "#" },
        .{ .value = self.stopBt.value(.{ .db = uib.button2 }) },
        .{ .label = "<" },
        .{ .value = self.startBt.value(.{ .db = uib.button3 }) },
        .{ .label = "o" },
        .{ .value = self.origBt.value(.{ .db = uib.button4 }) },
    };
}

fn startEnabled(dcgt: *DriveControlGotoTest) bool {
    return switch (dcgt.dc.state) {
        .stoped => true,
        else => false,
    };
}

fn startClicked(dcgt: *DriveControlGotoTest) void {
    dcgt.dc.goto(switch (dcgt.next_pos) {
        .min => dcgt.range.min.*,
        .max => dcgt.range.max.*,
    }) catch {};
    dcgt.next_pos = switch (dcgt.next_pos) {
        .min => .max,
        .max => .min,
    };
}

fn stopEnabled(dcgt: *DriveControlGotoTest) bool {
    return switch (dcgt.dc.state) {
        .moving, .go_to_origin => true,
        else => false,
    };
}

fn stopClicked(dcgt: *DriveControlGotoTest) void {
    dcgt.dc.stop() catch {};
}

fn origEnabled(dcgt: *DriveControlGotoTest) bool {
    return switch (dcgt.dc.state) {
        .stoped, .paused, .limited, .time_exceeded => true,
        else => false,
    };
}

fn origClicked(dcgt: *DriveControlGotoTest) void {
    dcgt.dc.goToOrigin() catch {};
}
