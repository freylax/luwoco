const DriveControl = @import("DriveControl.zig");
const values = @import("tui/values.zig");
const ClickButton = values.ClickButton;
const RoRefIntValue = values.RoRefIntValue;
const items = @import("tui/items.zig");
const Value = items.Value;

const Self = @This();

const ClickBt = ClickButton(DriveControl);
const Int = RoRefIntValue(i8, 3, 10);

fwBt: ClickBt,
bwBt: ClickBt,
stopBt: ClickBt,
lastPos: Int,
targetPos: Int,

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
        .lastPos = .{ .ref = &dc.last_pos },
        .targetPos = .{ .ref = &dc.target_pos },
    };
}

fn stepForwardEnabled(dc: *DriveControl) bool {
    return switch (dc.state) {
        .idle, .stoped, .stoped_by_min => true,
        else => false,
    };
}

fn stepForwardClicked(dc: *DriveControl) void {
    dc.stepForward() catch {};
}

fn stepBackwardEnabled(dc: *DriveControl) bool {
    return switch (dc.state) {
        .idle, .stoped, .stoped_by_max => true,
        else => false,
    };
}

fn stepBackwardClicked(dc: *DriveControl) void {
    dc.stepBackward() catch {};
}

fn stopEnabled(dc: *DriveControl) bool {
    return switch (dc.state) {
        .driving => true,
        else => false,
    };
}

fn stopClicked(dc: *DriveControl) void {
    dc.stop() catch {};
}
