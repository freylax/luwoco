const std = @import("std");
const microzig = @import("microzig");
const peripherals = microzig.chip.peripherals;
const Config = @import("Config.zig");
const Drive = @import("Drive.zig");
const Relais = @import("Relais.zig");
const SampleButton = @import("SampleButton.zig");
const DriveControl = @import("DriveControl.zig");
const MotionSimulator = @import("MotionSimulator.zig");
const CurrentSensor = @import("CurrentSensor.zig");
const PosControl = @import("PosControl.zig");
const rp2xxx = microzig.hal;
const gpio = rp2xxx.gpio;
const time = rp2xxx.time;
const GPIO_Device = rp2xxx.drivers.GPIO_Device;
const I2C_Device = rp2xxx.drivers.I2C_Device;

const Self = @This();

const pin_config = rp2xxx.pins.GlobalConfiguration{
    .GPIO0 = .{ .name = "gpio0", .function = .UART0_TX },
    .GPIO4 = .{ .name = "sda", .function = .I2C0_SDA, .slew_rate = .slow, .schmitt_trigger = .enabled },
    .GPIO5 = .{ .name = "scl", .function = .I2C0_SCL, .slew_rate = .slow, .schmitt_trigger = .enabled },
    .GPIO6 = .{ .name = "lcd_reset", .direction = .out },
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
    .GPIO19 = .{ .name = "pos_y_pos", .direction = .in, .pull = .up },
    .GPIO20 = .{ .name = "pos_y_min", .direction = .in, .pull = .up },
    .GPIO21 = .{ .name = "pos_y_max", .direction = .in, .pull = .up },
    .GPIO25 = .{ .name = "led", .direction = .out },
};

const pins = pin_config.pins();

const iod = struct {
    var lcd_reset = GPIO_Device.init(pins.lcd_reset);
    var pos_x_pos = GPIO_Device.init(pins.pos_x_pos);
    var pos_x_min = GPIO_Device.init(pins.pos_x_min);
    var pos_x_max = GPIO_Device.init(pins.pos_x_max);
    var pos_y_pos = GPIO_Device.init(pins.pos_y_pos);
    var pos_y_min = GPIO_Device.init(pins.pos_y_min);
    var pos_y_max = GPIO_Device.init(pins.pos_y_max);
    var drive_x_enable = GPIO_Device.init(pins.drive_x_enable);
    var drive_x_dir_a = GPIO_Device.init(pins.drive_x_dir_a);
    var drive_x_dir_b = GPIO_Device.init(pins.drive_x_dir_b);
    var drive_y_enable = GPIO_Device.init(pins.drive_y_enable);
    var drive_y_dir_a = GPIO_Device.init(pins.drive_y_dir_a);
    var drive_y_dir_b = GPIO_Device.init(pins.drive_y_dir_b);
    var relais_a = GPIO_Device.init(pins.relais_a);
    var relais_b = GPIO_Device.init(pins.relais_b);
};

pub const uart0 = rp2xxx.uart.instance.num(0);
const baud_rate = 115200;
pub const i2c0 = rp2xxx.i2c.instance.num(0);
pub var lcd_reset = iod.lcd_reset.digital_io();
// not io related, but let live here for now.
pub var use_simulator: bool = false;

pub var i2c_device = I2C_Device.init(i2c0, null);
pub var x_sim = MotionSimulator{
    .switching_time_cs = &Config.values.simulator_switching_time_cs,
    .driving_time_s = &Config.values.simulator_driving_time_s,
    .active = .low,
    .inactive = .high,
    .min_pin = .high,
    .max_pin = .high,
    .pos_pin = .low,
};
pub var y_sim = MotionSimulator{
    .switching_time_cs = &Config.values.simulator_switching_time_cs,
    .driving_time_s = &Config.values.simulator_driving_time_s,
    .active = .low,
    .inactive = .high,
    .min_pin = .high,
    .max_pin = .high,
    .pos_pin = .low,
};
pub var pos_x_pos = SampleButton{
    .pin = iod.pos_x_pos.digital_io(),
    .active = .low,
    .simulator_pin = &x_sim.pos_pin,
    .use_simulator = &use_simulator,
};
pub var pos_x_min = SampleButton{
    .pin = iod.pos_x_min.digital_io(),
    .active = .low,
    .simulator_pin = &x_sim.min_pin,
    .use_simulator = &use_simulator,
};
pub var pos_x_max = SampleButton{
    .pin = iod.pos_x_max.digital_io(),
    .active = .low,
    .simulator_pin = &x_sim.max_pin,
    .use_simulator = &use_simulator,
};
pub var pos_y_pos = SampleButton{
    .pin = iod.pos_y_pos.digital_io(),
    .active = .low,
    .simulator_pin = &y_sim.pos_pin,
    .use_simulator = &use_simulator,
};
pub var pos_y_min = SampleButton{
    .pin = iod.pos_y_min.digital_io(),
    .active = .low,
    .simulator_pin = &y_sim.min_pin,
    .use_simulator = &use_simulator,
};
pub var pos_y_max = SampleButton{
    .pin = iod.pos_y_max.digital_io(),
    .active = .low,
    .simulator_pin = &y_sim.max_pin,
    .use_simulator = &use_simulator,
};
pub var drive_x = Drive{
    .enable = iod.drive_x_enable.digital_io(),
    .dir_a = iod.drive_x_dir_a.digital_io(),
    .dir_b = iod.drive_x_dir_b.digital_io(),
    .sim_enable = &x_sim.enable_pin,
    .sim_dir_a = &x_sim.dir_a_pin,
    .sim_dir_b = &x_sim.dir_b_pin,
    .use_simulator = &use_simulator,
};
pub var drive_y = Drive{
    .enable = iod.drive_y_enable.digital_io(),
    .dir_a = iod.drive_y_dir_a.digital_io(),
    .dir_b = iod.drive_y_dir_b.digital_io(),
    .sim_enable = &y_sim.enable_pin,
    .sim_dir_a = &y_sim.dir_a_pin,
    .sim_dir_b = &y_sim.dir_b_pin,
    .use_simulator = &use_simulator,
};
pub var relais_a = Relais{ .pin = iod.relais_a.digital_io() };
pub var relais_b = Relais{ .pin = iod.relais_b.digital_io() };
pub var drive_x_control = DriveControl{
    .drive = &drive_x,
    .pos_bt = &pos_x_pos,
    .min_bt = &pos_x_min,
    .max_bt = &pos_x_max,
    .min_coord = &Config.values.allowed_area.x.min,
    .max_coord = &Config.values.allowed_area.x.max,
};
pub var drive_y_control = DriveControl{
    .drive = &drive_y,
    .pos_bt = &pos_y_pos,
    .min_bt = &pos_y_min,
    .max_bt = &pos_y_max,
    .min_coord = &Config.values.allowed_area.y.min,
    .max_coord = &Config.values.allowed_area.y.max,
};

pub var current_sensor_enable: bool = false;

pub var current_sensor = CurrentSensor{
    .input = .ain0, //.temp_sensor,
    .enable = &current_sensor_enable,
    .nr_of_samples = &Config.values.current_sensor_nr_of_samples,
    .pause_time_cs = &Config.values.current_sensor_pause_time_cs,
};

pub var pos_control = PosControl{
    .drive_x_control = &drive_x_control,
    .drive_y_control = &drive_y_control,
    .switch_relais = &relais_a,
    .current_sensor_enable = &current_sensor_enable,
    .current_sensor_value = &current_sensor.value,
    .current_sensor_threshold = &Config.values.current_sensor_threshold,
    .cooking_time_dm = &Config.values.cooking_time_dm,
    .cooling_time_dm = &Config.values.cooling_time_dm,
    .work_area = wablk: {
        const wa = &Config.values.work_area;
        break :wablk .{
            .x = .{ .min = &wa.x.min, .max = &wa.x.max },
            .y = .{ .min = &wa.y.min, .max = &wa.y.max },
        };
    },
};

pub fn init() !void {
    pin_config.apply();
    // interrupt set enable register
    peripherals.PPB.NVIC_ISER.modify(.{
        .SETENA = 1 << 13, // 13 is IO_IRQ_BANK0
    });

    peripherals.IO_BANK0.PROC0_INTE2.modify(.{
        .GPIO16_EDGE_LOW = 1,
        .GPIO16_EDGE_HIGH = 1,
        .GPIO17_EDGE_LOW = 1,
        .GPIO17_EDGE_HIGH = 1,
        .GPIO18_EDGE_LOW = 1,
        .GPIO18_EDGE_HIGH = 1,
        .GPIO19_EDGE_LOW = 1,
        .GPIO19_EDGE_HIGH = 1,
        .GPIO20_EDGE_LOW = 1,
        .GPIO20_EDGE_HIGH = 1,
        .GPIO21_EDGE_LOW = 1,
        .GPIO21_EDGE_HIGH = 1,
    });
    uart0.apply(.{
        .baud_rate = baud_rate,
        .clock_config = rp2xxx.clock_config,
    });
    i2c0.apply(.{ .clock_config = rp2xxx.clock_config });
}

pub fn begin() !void {
    try lcd_reset.write(.high);
    try drive_x.begin();
    try drive_y.begin();

    try relais_a.begin();
    try relais_b.begin();

    current_sensor.begin();

    const t = time.get_time_since_boot();
    _ = try pos_x_pos.sample(t);
    _ = try pos_x_min.sample(t);
    _ = try pos_x_max.sample(t);
    _ = try pos_y_pos.sample(t);
    _ = try pos_y_min.sample(t);
    _ = try pos_y_max.sample(t);
    try drive_x_control.begin();
    try drive_y_control.begin();
}
