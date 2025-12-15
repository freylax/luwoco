const values = @import("tui/values.zig");
const IntValue = values.IntValue;
const RoRefIntValue = values.RoRefIntValue;
const EnumRefValue = values.EnumRefValue;
const RefPushButton = values.RefPushButton;
const PushButton = values.PushButton;
const ClickButton = values.ClickButton;
const Config = @import("Config.zig");
const Item = @import("tui/Tree.zig").Item;
const CookTime = @import("CookTime.zig");

const Self = @This();

const Humidity = EnumRefValue(CookTime.Humidity, [_][]const u8{ "moist", "semim", "dry" });

const U8Value = IntValue(*u8, u8, 4, 10);
use_mapping: RefPushButton(bool),
humidity: Humidity,
depth: U8Value,
cooking_time: U8Value,
cooling_time: U8Value,

pub fn create(use_mapping: *bool, humidity: *CookTime.Humidity, depth: *u8, cooking_time: *u8, cooling_time: *u8, id: u16) Self {
    return .{
        .use_mapping = .{
            .ref = use_mapping,
            .pressed = true,
            .released = false,
            .id = id,
        },
        .humidity = .{
            .ref = humidity,
            .id = id,
        },
        .depth = .{ .val = depth, .range = .{ .min = 1, .max = CookTime.max_depth }, .id = id },
        .cooking_time = .{ .val = cooking_time, .range = .{ .min = 0, .max = 150 }, .id = id },
        .cooling_time = .{ .val = cooling_time, .range = .{ .min = 0, .max = 40 }, .id = id },
    };
}

pub fn ui(self: *Self) []const Item {
    return &.{
        .{ .label = "use map " },
        .{ .value = self.use_mapping.value(.{}) }, // 3
        .{ .label = "\n" },
        .{ .label = "humidity:" },
        .{ .value = self.humidity.value(.rw) },
        .{ .label = "\n" },
    };
}
