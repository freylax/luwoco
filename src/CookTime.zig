const Config = @import("Config.zig");

const Self = @This();

// // mapping of humidity,
pub const Humidity = enum(u2) { moist = 0, semi_moist = 1, dry = 2 };
// mapping of humidity and thickness in cm to cook time in deciminutes
pub const max_depth = 26;
const mapping = [3][max_depth + 1]u8{
    [_]u8{ 20, 30, 35, 40, 43, 47, 50, 52, 55, 57, 60, 62, 65, 67, 70, 72, 75, 77, 80, 82, 85, 87, 90, 92, 95, 97, 100 },
    [_]u8{ 30, 50, 52, 54, 56, 58, 60, 62, 65, 67, 70, 72, 75, 77, 80, 85, 90, 95, 100, 105, 110, 115, 120, 125, 130, 135, 140 },
    [_]u8{ 40, 60, 62, 64, 66, 68, 70, 72, 75, 77, 80, 82, 85, 87, 90, 95, 100, 110, 120, 125, 130, 133, 137, 140, 143, 147, 150 },
};
// mapping of cook time to pause time
pub fn cooling_time(cook_time: u8) u8 {
    return if (cook_time < 30)
        10
    else if (cook_time > 150)
        40
    else
        10 + @as(u8, @truncate(((@as(u32, cook_time) - 30) * 30) / 120));
}

pub fn update() void {
    const use = &Config.values.use_depth_time_mapping;
    const humidity = &Config.values.humidity;
    const depth = &Config.values.penetration_depth_cm;
    const cooking = &Config.values.cooking_time_dm;
    const cooling = &Config.values.cooking_time_dm;
    if (use.*) {
        cooking.* = mapping[@intFromEnum(humidity.*)][@min(max_depth, depth.*)];
        cooling.* = cooling_time(cooking.*);
    }
}
