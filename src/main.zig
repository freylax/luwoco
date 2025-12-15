const std = @import("std");
const microzig = @import("microzig");
const peripherals = microzig.chip.peripherals;
const Digital_IO = microzig.drivers.base.Digital_IO;
const IOState = Digital_IO.State;
const olimex_lcd = @import("olimex_lcd.zig");
const Drive = @import("Drive.zig");
const Relais = @import("Relais.zig");
const Buttons = @import("tui/Buttons.zig");
const DriveControlUI = @import("DriveControlUI.zig");
const DriveControlGotoTestUI = @import("DriveControlGotoTestUI.zig");
const PosControlUI = @import("PosControlUI.zig");
const CookTime = @import("CookTime.zig");
const CookTimeUI = @import("CookTimeUI.zig");
const Tree = @import("tui/Tree.zig");
const TUI = @import("TUI.zig");
const IO = @import("IO.zig");
const areaUI = @import("areaUI.zig");
const rangeUI = @import("rangeUI.zig");
const Item = Tree.Item;
const values = @import("tui/values.zig");
const uib = @import("ui_buttons.zig");
const IntValue = values.IntValue;
const RoRefIntValue = values.RoRefIntValue;
const RefBoolValue = values.RefBoolValue;
const RefPushButton = values.RefPushButton;
const PushButton = values.PushButton;
const ClickButton = values.ClickButton;
const BulbValue = values.BulbValue;
const Config = @import("Config.zig");
const FlashJournal = @import("FlashJournal.zig");

const rp2xxx = microzig.hal;
const time = rp2xxx.time;
const gpio = rp2xxx.gpio;
const Mutex = rp2xxx.mutex.Mutex;
const multicore = rp2xxx.multicore;
const fifo = multicore.fifo;
const log = std.log;
const assert = std.debug.assert;
const system_timer = rp2xxx.system_timer;
const timer0 = system_timer.num(0);

pub const microzig_options = microzig.Options{
    .log_level = .info,
    .logFn = rp2xxx.uart.log,
    .interrupts = .{
        .TIMER_IRQ_0 = .{ .c = timer_interrupt_handler },
        .IO_IRQ_BANK0 = .{ .c = switch_interrupt_handler },
    },
};

const EventId = enum(u16) {
    config,
    back_light,
    set_timer_interrupt,
    drive_x,
    drive_y,
    relais_a,
    relais_b,
    cook_time,
    pub fn id(self: EventId) u16 {
        return @intFromEnum(self);
    }
};

const EventTag = enum {
    tui,
    cfg,
};

const Event = struct {
    id: EventId,
    pl: union(EventTag) {
        tui: TUI.Event.PayLoad,
        cfg: void,
    },
};

const BS = TUI.ButtonSemantics;

const button_masks = blk: {
    const l = TUI.ButtonSemanticsLen;
    var a = [_]u8{0} ** l;
    a[@intFromEnum(BS.escape)] = uib.button1;
    a[@intFromEnum(BS.left)] = uib.button2;
    a[@intFromEnum(BS.right)] = uib.button3;
    a[@intFromEnum(BS.activate)] = uib.button4;
    break :blk a;
};

var back_light = IntValue(*u8, u8, 4, 10){ .range = .{ .min = 0, .max = 255 }, .val = &Config.values.back_light, .id = EventId.back_light.id() };

var after_move_time = IntValue(*u8, u8, 4, 10){ .range = .{ .min = 0, .max = 255 }, .val = &Config.values.after_move_time_ds };
var skip_cooking = RefPushButton(bool){ .ref = &IO.skip_cooking, .pressed = true, .released = false };
const AreaUIV = areaUI.AreaUI(*i8, i8, 3);
var allowed_area = aablk: {
    const a = &Config.values.allowed_area;
    break :aablk AreaUIV.create(
        .{
            .x = .{ .min = &a.x.min, .max = &a.x.max },
            .y = .{ .min = &a.y.min, .max = &a.y.max },
        },
        .{ .min = -10, .max = 0 },
        .{ .min = 0, .max = 10 },
        .{ .min = -5, .max = 0 },
        .{ .min = 0, .max = 5 },
    );
};
const AreaUIR = areaUI.AreaUI(*i8, *const i8, 3);
var work_area = wablk: {
    const aa = &Config.values.allowed_area;
    const wa = &Config.values.work_area;
    const zero: i8 = 0;
    break :wablk AreaUIR.create(
        .{
            .x = .{ .min = &wa.x.min, .max = &wa.x.max },
            .y = .{ .min = &wa.y.min, .max = &wa.y.max },
        },
        .{ .min = &aa.x.min, .max = &zero },
        .{ .min = &zero, .max = &aa.x.max },
        .{ .min = &aa.y.min, .max = &zero },
        .{ .min = &zero, .max = &aa.y.max },
    );
};
const RangeUI = rangeUI.RangeUI(*i8, i8, 3);
var x_goto_test = xgblk: {
    const r = &Config.values.x_goto_test_range;
    break :xgblk RangeUI.create(
        .{ .min = &r.min, .max = &r.max },
        .{ .min = -10, .max = 10 },
        .{ .min = -10, .max = 10 },
    );
};
var y_goto_test = ygblk: {
    const r = &Config.values.y_goto_test_range;
    break :ygblk RangeUI.create(
        .{ .min = &r.min, .max = &r.max },
        .{ .min = -5, .max = 5 },
        .{ .min = -5, .max = 5 },
    );
};
var x_max_segment_duration_ds = IntValue(*u8, u8, 4, 10){
    .range = .{ .min = 0, .max = 255 },
    .val = &Config.values.x_max_segment_duration_ds,
};
var y_max_segment_duration_ds = IntValue(*u8, u8, 4, 10){
    .range = .{ .min = 0, .max = 255 },
    .val = &Config.values.y_max_segment_duration_ds,
};
var x_lim_check_delay_cs = IntValue(*u8, u8, 4, 10){
    .range = .{ .min = 0, .max = 255 },
    .val = &Config.values.x_lim_check_delay_cs,
};
var y_lim_check_delay_cs = IntValue(*u8, u8, 4, 10){
    .range = .{ .min = 0, .max = 255 },
    .val = &Config.values.y_lim_check_delay_cs,
};
var timer_sampling_time_cs = IntValue(*u8, u8, 4, 10){
    .range = .{ .min = 1, .max = 255 },
    .val = &Config.values.timer_sampling_time_cs,
};
var simulator_sampling_time_cs = IntValue(*u8, u8, 4, 10){
    .range = .{ .min = 1, .max = 255 },
    .val = &Config.values.simulator_sampling_time_cs,
};
var simulator_switching_time_cs = IntValue(*u8, u8, 4, 10){
    .range = .{ .min = 0, .max = 255 },
    .val = &Config.values.simulator_switching_time_cs,
};
var simulator_driving_time_s = IntValue(*u8, u8, 4, 10){
    .range = .{ .min = 0, .max = 255 },
    .val = &Config.values.simulator_driving_time_s,
};
var simulator_delaying_time_cs = IntValue(*u8, u8, 4, 10){
    .range = .{ .min = 0, .max = 255 },
    .val = &Config.values.simulator_delaying_time_cs,
};
var use_simulator = RefPushButton(bool){
    .ref = &IO.use_simulator,
    .pressed = true,
    .released = false,
    .id = EventId.set_timer_interrupt.id(),
};
fn is_simulator_used() bool {
    return IO.use_simulator;
}
var use_delaying = RefPushButton(bool){
    .ref = &IO.use_delaying,
    .pressed = true,
    .released = false,
    .enabled = is_simulator_used,
};
var pb_cook_enable = RefPushButton(IOState){
    .ref = &IO.cook_enable_sim,
    .pressed = .low,
    .released = .high,
    .enabled = is_simulator_used,
};
var pb_save_config = ClickButton(Config){
    .ref = &Config.values,
    .enabled = Config.data_differ,
    .clicked = Config.write,
};
var cook_time_ui = CookTimeUI.create(
    &Config.values.use_depth_time_mapping,
    &Config.values.humidity,
    &Config.values.penetration_depth_cm,
    &Config.values.cooking_time_dm,
    &Config.values.cooling_time_dm,
    EventId.cook_time.id(),
);
var drive_x_state: Drive.State = .off;
var pb_dx_dir_a = RefPushButton(Drive.State){
    .ref = &drive_x_state,
    .pressed = .dir_a,
    .released = .off,
    .id = EventId.drive_x.id(),
};
var pb_dx_dir_b = RefPushButton(Drive.State){
    .ref = &drive_x_state,
    .pressed = .dir_b,
    .released = .off,
    .id = EventId.drive_x.id(),
};
var drive_y_state: Drive.State = .off;
var pb_dy_dir_a = RefPushButton(Drive.State){
    .ref = &drive_y_state,
    .pressed = .dir_a,
    .released = .off,
    .id = EventId.drive_y.id(),
};
var pb_dy_dir_b = RefPushButton(Drive.State){
    .ref = &drive_y_state,
    .pressed = .dir_b,
    .released = .off,
    .id = EventId.drive_y.id(),
};
var relais_a_state: Relais.State = .off;
var pb_relais_a = RefPushButton(Relais.State){
    .ref = &relais_a_state,
    .pressed = .on,
    .released = .off,
    .id = EventId.relais_a.id(),
};
var relais_b_state: Relais.State = .off;
var pb_relais_b = RefPushButton(Relais.State){
    .ref = &relais_b_state,
    .pressed = .on,
    .released = .off,
    .id = EventId.relais_b.id(),
};

var drive_x_ui = DriveControlUI.create(&IO.drive_x_control);
var drive_y_ui = DriveControlUI.create(&IO.drive_y_control);
var drive_x_goto_test_ui = DriveControlGotoTestUI.create(&IO.drive_x_goto_test, &IO.drive_x_control);
var drive_y_goto_test_ui = DriveControlGotoTestUI.create(&IO.drive_y_goto_test, &IO.drive_y_control);
var pos_ui = PosControlUI.create(&IO.pos_control, &IO.drive_x_control, &IO.drive_y_control);

const items: []const Item = &.{
    .{
        .popup = .{
            .id = EventId.config.id(),
            .str = " config\n",
            .items = &.{
                .{ .label = "Save: " },
                .{ .value = pb_save_config.value(.{}) },
                .{ .label = "\n" },
                .{ .popup = .{
                    .str = " allowed area\n",
                    .items = allowed_area.ui(),
                } },
                .{ .label = "after mv ds:" },
                .{ .value = after_move_time.value() },
                .{ .label = "x maxseg ds:" },
                .{ .value = x_max_segment_duration_ds.value() },
                // .{ .label = "\n" },
                .{ .label = "y maxseg ds:" },
                .{ .value = y_max_segment_duration_ds.value() },
                // .{ .label = "\n" },
                .{ .label = "x limckd cs:" },
                .{ .value = x_lim_check_delay_cs.value() },
                .{ .label = "y limckd cs:" },
                .{ .value = y_lim_check_delay_cs.value() },
                .{ .label = "smpl tm cs:" },
                .{ .value = timer_sampling_time_cs.value() },
                .{ .label = "\n" },
                .{ .popup = .{
                    .str = " simulator\n",
                    .items = &.{
                        .{ .label = "samp cs:" },
                        .{ .value = simulator_sampling_time_cs.value() },
                        .{ .label = "\nswit cs:" },
                        .{ .value = simulator_switching_time_cs.value() },
                        .{ .label = "\ndriv s:" },
                        .{ .value = simulator_driving_time_s.value() },
                        .{ .label = "\ndelay cs:" },
                        .{ .value = simulator_delaying_time_cs.value() },
                    },
                } },
                .{ .label = "Backlight:" },
                .{ .value = back_light.value() },
            },
        },
    },
    .{ .popup = .{ .str = " main\n", .items = &.{
        .{ .popup = .{
            .str = " pos control\n",
            .items = pos_ui.ui(),
        } },
        .{ .label = "Save cfg: " },
        .{ .value = pb_save_config.value(.{}) },
        .{ .label = "\n" },
        .{ .popup = .{
            .str = " work area\n",
            .items = work_area.ui(),
        } },
        .{ .popup = .{
            .str = " cook time\n",
            .items = cook_time_ui.ui(),
        } },
        .{ .label = "skip cook: " },
        .{ .value = skip_cooking.value(.{ .behaviour = .toggle_button }) },
    } } },
    .{
        .popup = .{
            .str = " drive control\n",
            .items = &.{
                .{ .popup = .{
                    .str = " drive X\n",
                    .items = drive_x_ui.ui(),
                } },
                .{ .popup = .{
                    .str = " drive Y\n",
                    .items = drive_y_ui.ui(),
                } },
                .{ .popup = .{
                    .str = " goto test\n",
                    .items = &.{
                        .{ .popup = .{
                            .str = " X setup\n",
                            .items = x_goto_test.ui(),
                        } },
                        .{ .popup = .{
                            .str = " X test\n",
                            .items = drive_x_goto_test_ui.ui(),
                        } },
                        .{ .popup = .{
                            .str = " Y setup\n",
                            .items = y_goto_test.ui(),
                        } },
                        .{ .popup = .{
                            .str = " Y test\n",
                            .items = drive_y_goto_test_ui.ui(),
                        } },
                        .{ .label = "Save cfg: " },
                        .{ .value = pb_save_config.value(.{}) },
                        .{ .label = "\n" },
                    },
                } },
            },
        },
    },
    .{
        .popup = .{
            .str = " sim,cook enbl\n",
            .items = &.{
                .{ .label = "cook enable:" },
                .{ .value = IO.cook_enable.sampleValue() },
                .{ .label = "\nsm" },
                .{ .value = use_simulator.value(.{ .db = uib.button2, .behaviour = .toggle_button }) },
                .{ .label = "en" },
                .{ .value = pb_cook_enable.value(.{ .db = uib.button3, .behaviour = .toggle_button }) },
                .{ .label = "dl" },
                .{ .value = use_delaying.value(.{ .db = uib.button4, .behaviour = .toggle_button }) },
            },
        },
    },
    .{ .popup = .{
        .str = " output test\n",
        .items = &.{
            .{ .popup = .{
                .str = " Drive X\n",
                .items = &.{
                    .{ .label = "    " },
                    .{ .label = " X-" },
                    .{ .value = pb_dx_dir_b.value(.{ .db = uib.button3 }) },
                    .{ .label = " X+" },
                    .{ .value = pb_dx_dir_a.value(.{ .db = uib.button4 }) },
                },
            } },
            .{ .popup = .{
                .str = " Drive Y\n",
                .items = &.{
                    .{ .label = "    " },
                    .{ .label = " Y-" },
                    .{ .value = pb_dy_dir_b.value(.{ .db = uib.button3 }) },
                    .{ .label = " Y+" },
                    .{ .value = pb_dy_dir_a.value(.{ .db = uib.button4 }) },
                },
            } },
            .{ .popup = .{
                .str = " Relais\n",
                .items = &.{
                    .{ .label = "    " },
                    .{ .label = " A " },
                    .{ .value = pb_relais_a.value(.{ .db = uib.button3, .behaviour = .toggle_button }) },
                    .{ .label = " B " },
                    .{ .value = pb_relais_b.value(.{ .db = uib.button4, .behaviour = .toggle_button }) },
                },
            } },
        },
    } },
    .{ .popup = .{
        .str = " input test\n",
        .items = &.{
            .{ .popup = .{
                .str = " read pos_x\n",
                .items = &.{
                    .{ .label = "read x pos:" },
                    .{ .value = IO.pos_x_pos.readValue() },
                    .{ .label = "\nori:" },
                    .{ .value = IO.pos_x_ori.readValue() },
                    .{ .label = " lim:" },
                    .{ .value = IO.pos_x_lim.readValue() },
                },
            } },
            .{ .popup = .{
                .str = " sample pos_x\n",
                .items = &.{
                    .{ .label = "sample x pos:" },
                    .{ .value = IO.pos_x_pos.sampleValue() },
                    .{ .label = "ori:" },
                    .{ .value = IO.pos_x_ori.sampleValue() },
                    .{ .label = " lim:" },
                    .{ .value = IO.pos_x_lim.sampleValue() },
                },
            } },
            .{ .popup = .{
                .str = " read pos_y\n",
                .items = &.{
                    .{ .label = "read y pos:" },
                    .{ .value = IO.pos_y_pos.readValue() },
                    .{ .label = "\nori:" },
                    .{ .value = IO.pos_y_ori.readValue() },
                    .{ .label = " lim:" },
                    .{ .value = IO.pos_y_lim.readValue() },
                },
            } },
            .{ .popup = .{
                .str = " sample pos_y\n",
                .items = &.{
                    .{ .label = "sample y pos:" },
                    .{ .value = IO.pos_y_pos.sampleValue() },
                    .{ .label = "ori:" },
                    .{ .value = IO.pos_y_ori.sampleValue() },
                    .{ .label = " lim:" },
                    .{ .value = IO.pos_y_lim.sampleValue() },
                },
            } },
        },
    } },
    .{
        .popup = .{
            .str = " Characters\n",
            .items = &.{.{
                .label = &.{
                    '0', '0', 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, '\n', //
                    '0', 'E', 0x0e, 0x0f, 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1a, 0x1b, '\n', //
                    '1', 'C', 0x1c, 0x1d, 0x1e, 0x1f, 0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28, 0x29, '\n', //
                    '2', 'A', 0x2a, 0x2b, 0x2c, 0x2d, 0x2e, 0x2f, 0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, '\n', //
                    '3', '8', 0x38, 0x39, 0x3a, 0x3b, 0x3c, 0x3d, 0x3e, 0x3f, 0x40, 0x41, 0x42, 0x43, 0x44, 0x45, '\n', //
                    '4', '6', 0x46, 0x47, 0x48, 0x49, 0x4a, 0x4b, 0x4c, 0x4d, 0x4e, 0x4f, 0x50, 0x51, 0x52, 0x53, '\n', //
                    '5', '4', 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5a, 0x5b, 0x5c, 0x5d, 0x5e, 0x5f, 0x60, 0x61, '\n', //
                    '6', '2', 0x62, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6a, 0x6b, 0x6c, 0x6d, 0x6e, 0x6f, '\n', //
                    '7', '0', 0x70, 0x71, 0x72, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7a, 0x7b, 0x7c, 0x7d, '\n', //
                    '7', 'E', 0x7e, 0x7f, 0x80, 0x81, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89, 0x8a, 0x8b, '\n', //
                    '8', 'C', 0x8c, 0x8d, 0x8e, 0x8f, 0x90, 0x91, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, '\n', //
                    '9', 'A', 0x9a, 0x9b, 0x9c, 0x9d, 0x9e, 0x9f, 0xa0, 0xa1, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7, '\n', //
                    'A', '8', 0xa8, 0xa9, 0xaa, 0xab, 0xac, 0xad, 0xae, 0xaf, 0xb0, 0xb1, 0xb2, 0xb3, 0xb4, 0xb5, '\n', //
                    'B', '6', 0xb6, 0xb7, 0xb8, 0xb9, 0xba, 0xbb, 0xbc, 0xbd, 0xbe, 0xbf, 0xc0, 0xc1, 0xc2, 0xc3, '\n', //
                    'C', '4', 0xc4, 0xc5, 0xc6, 0xc7, 0xc8, 0xc9, 0xca, 0xcb, 0xcc, 0xcd, 0xce, 0xcf, 0xd0, 0xd1, '\n', //
                    'D', '2', 0xd2, 0xd3, 0xd4, 0xd5, 0xd6, 0xd7, 0xd8, 0xd9, 0xda, 0xdb, 0xdc, 0xdd, 0xde, 0xdf, '\n', //
                    'E', '0', 0xe0, 0xe1, 0xe2, 0xe3, 0xe4, 0xe5, 0xe6, 0xe7, 0xe8, 0xe9, 0xea, 0xeb, 0xec, 0xed, '\n', //
                    'E', 'E', 0xee, 0xef, 0xf0, 0xf1, 0xf2, 0xf3, 0xf4, 0xf5, 0xf6, 0xf7, 0xf8, 0xf9, 0xfa, 0xfb, '\n', //
                    'F', 'C', 0xfc, 0xfd, 0xfe, 0xff,
                },
            }},
        },
    },
};

fn set_timer_interrupt() void {
    microzig.interrupt.enable(.TIMER_IRQ_0);
    timer0.set_interrupt_enabled(.alarm0, true);
    if (IO.use_simulator) {
        // set alarm
        const dt_us = @as(u32, @max(Config.values.simulator_sampling_time_cs, 1)) *| 10_000;
        timer0.schedule_alarm(.alarm0, timer0.read_low() +% dt_us);
    } else {
        const dt_us = @as(u32, @max(Config.values.timer_sampling_time_cs, 1)) *| 10_000;
        timer0.schedule_alarm(.alarm0, timer0.read_low() +% dt_us);
    }
}
fn timer_interrupt_handler() callconv(.c) void {
    const cs = microzig.interrupt.enter_critical_section();
    defer cs.leave();
    const t = time.get_time_since_boot();
    var dt_us: u32 = undefined;
    if (IO.use_simulator) {
        IO.x_sim.sample(t); // set state of input devices
        IO.y_sim.sample(t);
        dt_us = @as(u32, @max(Config.values.simulator_sampling_time_cs, 1)) *| 10_000;
    } else {
        dt_us = @as(u32, @max(Config.values.timer_sampling_time_cs, 1)) *| 10_000;
    }
    if (IO.pos_control.sample(t)) {} else |_| {}
    timer0.clear_interrupt(.alarm0);
    timer0.schedule_alarm(.alarm0, timer0.read_low() +% dt_us);
}

pub fn switch_interrupt_handler() callconv(.c) void {
    // disable interrupts
    const cs = microzig.interrupt.enter_critical_section();
    defer cs.leave(); // enable interrupts
    const IO_BANK0 = peripherals.IO_BANK0;
    const r = IO_BANK0.INTR2.read();
    // confirm the interrupt
    IO_BANK0.INTR2.write(r);
    const t = time.get_time_since_boot();
    if (IO.pos_control.sample(t)) {} else |_| {}
}

const tree = Tree.create(items, 16 - 1, 3000);
const LCD = olimex_lcd.BufferedLCD(tree.bufferLines);
const TuiImpl = TUI.Impl(tree, &button_masks);

pub fn main() !void {
    Config.read(&Config.values);
    try IO.init();
    // init uart logging
    rp2xxx.uart.init_logger(IO.uart0);

    std.log.info("setup lcd", .{});
    var lcd = LCD.init(IO.i2c_device.i2c_device(), @enumFromInt(0x30), IO.lcd_reset);
    var display = lcd.display();
    var buttons = lcd.buttons();
    var tuiImpl = TuiImpl.init(display);
    var tui = tuiImpl.tui();
    time.sleep_ms(100);

    try IO.begin();

    // we need some time after boot for i2c to become ready, otherwise
    // unsupported will be thrown
    time.sleep_ms(1000);
    _ = lcd.setBackLight(Config.values.back_light);
    display.cursor(0, 0, 0, 0, .select);
    time.sleep_ms(100);
    set_timer_interrupt();
    while (true) {
        var events: [8]Event = undefined;
        var ev_idx: u8 = 0;
        tui.writeValues();
        if (tui.print()) {} else |_| {}
        time.sleep_ms(100);
        const read_buttons = buttons.read();
        if (read_buttons) |b| {
            for (tui.buttonEvent(b)) |ev| {
                if (ev_idx < events.len) {
                    events[ev_idx] = .{ .id = @enumFromInt(ev.id), .pl = .{ .tui = ev.pl } };
                    ev_idx += 1;
                }
            }
        } else |_| {}
        if (lcd.lastError) |e| {
            switch (e) {
                error.DeviceNotPresent => log.err("DeviceNotPresent", .{}),
                error.NoAcknowledge => log.err("NoAcknowledge", .{}),
                error.Timeout => log.err("Timeout", .{}),
                error.TargetAddressReserved => log.err("TargetAddressReserved", .{}),
                error.NoData => log.err("NoData", .{}),
                error.BufferOverrun => log.err("BufferOverrun", .{}),
                error.UnknownAbort => log.err("UnknownAbort", .{}),
                error.IllegalAddress => log.err("IllegalAddress", .{}),
                error.Unsupported => log.err("Unsupported", .{}),
            }
            lcd.lastError = null;
        }
        for (events[0..ev_idx], 0..) |ev, ev_i| {
            log.info("process event ({d}/{d})", .{ ev_i, ev_idx });
            switch (ev.id) {
                .config => {
                    switch (ev.pl.tui.section) {
                        .enter => {
                            log.info("Enter Config Menu", .{});
                        },
                        .leave => {
                            log.info("Leave Config Menu", .{});
                        },
                    }
                },
                .back_light => {
                    log.info("back_light event", .{});
                    _ = lcd.setBackLight(back_light.val.*);
                },
                .set_timer_interrupt => {
                    set_timer_interrupt();
                },
                .drive_x => {
                    try IO.drive_x.set(drive_x_state);
                },
                .drive_y => {
                    try IO.drive_y.set(drive_y_state);
                },
                .relais_a => {
                    try IO.relais_a.set(relais_a_state);
                },
                .relais_b => {
                    try IO.relais_b.set(relais_b_state);
                },
                .cook_time => {
                    CookTime.update();
                },
            }
        }
    }
}
test {
    _ = FlashJournal;
}
