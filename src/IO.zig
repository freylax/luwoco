const std = @import("std");
const microzig = @import("microzig");
const peripherals = microzig.chip.peripherals;
const Drive = @import("Drive.zig");
const Relais = @import("Relais.zig");
const IntrButton = @import("IntrButton.zig");
const PositionSensor = @import("PositionSensor.zig");
const rp2xxx = microzig.hal;
const gpio = rp2xxx.gpio;
const GPIO_Device = rp2xxx.drivers.GPIO_Device;

const Self = @This();

const pin_config = rp2xxx.pins.GlobalConfiguration{
    .GPIO8 = .{ .name = "drive_x_enable", .direction = .out },
    .GPIO9 = .{ .name = "drive_x_dir_a", .direction = .out },
    .GPIO10 = .{ .name = "drive_x_dir_b", .direction = .out },
    .GPIO11 = .{ .name = "drive_y_enable", .direction = .out },
    .GPIO12 = .{ .name = "drive_y_dir_a", .direction = .out },
    .GPIO13 = .{ .name = "drive_y_dir_b", .direction = .out },
    .GPIO14 = .{ .name = "relais_a", .direction = .out },
    .GPIO15 = .{ .name = "relais_b", .direction = .out },
    .GPIO16 = .{ .name = "pos_x_pos", .direction = .in, .pull = .up },
    .GPIO17 = .{ .name = "pos_x_min", .direction = .in, .pull = .up },
    .GPIO18 = .{ .name = "pos_x_max", .direction = .in, .pull = .up },
};

const pins = pin_config.pins();

const iod = struct {
    var pos_x_pos = GPIO_Device.init(pins.pos_x_pos);
    var pos_x_min = GPIO_Device.init(pins.pos_x_min);
    var pos_x_max = GPIO_Device.init(pins.pos_x_max);
    var drive_x_enable = GPIO_Device.init(pins.drive_x_enable);
    var drive_x_dir_a = GPIO_Device.init(pins.drive_x_dir_a);
    var drive_x_dir_b = GPIO_Device.init(pins.drive_x_dir_b);
    var drive_y_enable = GPIO_Device.init(pins.drive_y_enable);
    var drive_y_dir_a = GPIO_Device.init(pins.drive_y_dir_a);
    var drive_y_dir_b = GPIO_Device.init(pins.drive_y_dir_b);
    var relais_a = GPIO_Device.init(pins.relais_a);
    var relais_b = GPIO_Device.init(pins.relais_b);
};

pub var pos_x_pos = IntrButton{ .pin = iod.pos_x_pos.digital_io(), .active = .low };
pub var pos_x_min = IntrButton{ .pin = iod.pos_x_min.digital_io(), .active = .low };
pub var pos_x_max = IntrButton{ .pin = iod.pos_x_max.digital_io(), .active = .low };
pub var drive_x = Drive{
    .enable = iod.drive_x_enable.digital_io(),
    .dir_a = iod.drive_x_dir_a.digital_io(),
    .dir_b = iod.drive_x_dir_b.digital_io(),
};
pub var drive_y = Drive{
    .enable = iod.drive_y_enable.digital_io(),
    .dir_a = iod.drive_y_dir_a.digital_io(),
    .dir_b = iod.drive_y_dir_b.digital_io(),
};
pub var relais_a = Relais{ .pin = iod.relais_a.digital_io() };
pub var relais_b = Relais{ .pin = iod.relais_b.digital_io() };

pub fn init() void {
    pin_config.apply();
}

pub fn begin() !void {
    try drive_x.begin();
    try drive_y.begin();

    try relais_a.begin();
    try relais_b.begin();
}
