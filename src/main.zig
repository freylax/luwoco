const std = @import("std");
const microzig = @import("microzig");
const peripherals = microzig.chip.peripherals;
const olimex_lcd = @import("olimex_lcd.zig");
const Drive = @import("Drive.zig");
const Relais = @import("Relais.zig");
const Buttons = @import("tui/Buttons.zig");
const DriveControlUI = @import("DriveControlUI.zig");
const PosControlUI = @import("PosControlUI.zig");
const Tree = @import("tui/Tree.zig");
const TUI = @import("TUI.zig");
const IO = @import("IO.zig");
const areaUI = @import("areaUI.zig");
const Item = Tree.Item;
const values = @import("tui/values.zig");
const uib = @import("ui_buttons.zig");
const IntValue = values.IntValue;
// const RefIntValue = values.RefIntValue;
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
        .TIMER_IRQ_0 = .{ .c = simulator_interrupt_handler },
        .IO_IRQ_BANK0 = .{ .c = switch_interrupt_handler },
    },
};

const EventId = enum(u16) {
    config,
    back_light,
    use_simulator,
    drive_x,
    drive_y,
    relais_a,
    relais_b,
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

var use_simulator = RefBoolValue{ .ref = &IO.use_simulator, .id = EventId.use_simulator.id() };

var pb_save_config = ClickButton(Config){
    .ref = &Config.values,
    .enabled = Config.data_differ,
    .clicked = Config.write,
};

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
var pos_ui = PosControlUI.create(&IO.pos_control, &IO.drive_x_control, &IO.drive_y_control);

const items: []const Item = &.{
    .{ .popup = .{
        .id = EventId.config.id(),
        .str = " Config\n",
        .items = &.{
            .{ .label = "Save: " },
            .{ .value = pb_save_config.value(.{}) },
            .{ .label = "\n" },
            .{ .popup = .{
                .str = " work area\n",
                .items = work_area.ui(),
            } },
            .{ .popup = .{
                .str = " allowed area\n",
                .items = allowed_area.ui(),
            } },
            .{ .label = "Backlight:" },
            .{ .value = back_light.value() },
        },
    } },
    .{ .popup = .{
        .str = " pos control\n",
        .items = pos_ui.ui(),
    } },
    .{ .popup = .{
        .str = " output test\n",
        .items = &.{
            .{ .popup = .{
                .str = " Test Drive X\n",
                .items = &.{
                    .{ .label = "    " },
                    .{ .label = " X+" },
                    .{ .value = pb_dx_dir_a.value(.{ .db = uib.button3 }) },
                    .{ .label = " X-" },
                    .{ .value = pb_dx_dir_b.value(.{ .db = uib.button4 }) },
                },
            } },
            .{ .popup = .{
                .str = " Test Drive y\n",
                .items = &.{
                    .{ .label = "    " },
                    .{ .label = " y+" },
                    .{ .value = pb_dy_dir_a.value(.{ .db = uib.button3 }) },
                    .{ .label = " y-" },
                    .{ .value = pb_dy_dir_b.value(.{ .db = uib.button4 }) },
                },
            } },
            .{ .popup = .{
                .str = " Relais Test\n",
                .items = &.{
                    .{ .label = "    " },
                    .{ .label = " A " },
                    .{ .value = pb_relais_a.value(.{ .db = uib.button3 }) },
                    .{ .label = " B " },
                    .{ .value = pb_relais_b.value(.{ .db = uib.button4 }) },
                },
            } },
        },
    } },
    .{ .popup = .{ .str = " control test\n", .items = &.{
        .{ .popup = .{
            .str = " drive x\n",
            .items = drive_x_ui.ui(),
        } },
        .{ .popup = .{
            .str = " drive y\n",
            .items = drive_y_ui.ui(),
        } },
        .{ .label = "simulator:" },
        .{ .value = use_simulator.value() },
    } } },
    .{ .popup = .{
        .str = " input test\n",
        .items = &.{
            .{ .popup = .{
                .str = " read pos_x\n",
                .items = &.{
                    .{ .label = "read x pos:" },
                    .{ .value = IO.pos_x_pos.readValue() },
                    .{ .label = "\nmin:" },
                    .{ .value = IO.pos_x_min.readValue() },
                    .{ .label = " max:" },
                    .{ .value = IO.pos_x_max.readValue() },
                },
            } },
            .{ .popup = .{
                .str = " sample pos_x\n",
                .items = &.{
                    .{ .label = "sample x pos:" },
                    .{ .value = IO.pos_x_pos.sampleValue() },
                    .{ .label = "min:" },
                    .{ .value = IO.pos_x_min.sampleValue() },
                    .{ .label = " max:" },
                    .{ .value = IO.pos_x_max.sampleValue() },
                },
            } },
            .{ .popup = .{
                .str = " read pos_y\n",
                .items = &.{
                    .{ .label = "read y pos:" },
                    .{ .value = IO.pos_y_pos.readValue() },
                    .{ .label = "\nmin:" },
                    .{ .value = IO.pos_y_min.readValue() },
                    .{ .label = " max:" },
                    .{ .value = IO.pos_y_max.readValue() },
                },
            } },
            .{ .popup = .{
                .str = " sample pos_y\n",
                .items = &.{
                    .{ .label = "sample y pos:" },
                    .{ .value = IO.pos_y_pos.sampleValue() },
                    .{ .label = "min:" },
                    .{ .value = IO.pos_y_min.sampleValue() },
                    .{ .label = " max:" },
                    .{ .value = IO.pos_y_max.sampleValue() },
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

fn switch_simulator_interrupt() void {
    if (IO.use_simulator) {
        microzig.interrupt.enable(.TIMER_IRQ_0);
        timer0.set_interrupt_enabled(.alarm0, true);
        // set alarm for 1 second
        timer0.schedule_alarm(.alarm0, timer0.read_low() +% 1_000_000);
    } else {
        timer0.set_interrupt_enabled(.alarm0, false);
    }
}
fn simulator_interrupt_handler() callconv(.c) void {
    const cs = microzig.interrupt.enter_critical_section();
    defer cs.leave();

    const t = time.get_time_since_boot();
    IO.x_sim.sample(t); // set state of input devices
    IO.y_sim.sample(t);
    // if (IO.drive_x_control.sample(t)) {} else |_| {}
    // if (IO.drive_y_control.sample(t)) {} else |_| {}
    if (IO.pos_control.sample(t)) {} else |_| {}

    timer0.clear_interrupt(.alarm0);
    // set alarm for 1 second
    timer0.schedule_alarm(.alarm0, timer0.read_low() +% 1_000_000);
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
    // if (IO.drive_x_control.sample(t)) {} else |_| {}
    // if (IO.drive_y_control.sample(t)) {} else |_| {}
    if (IO.pos_control.sample(t)) {} else |_| {}
    // intr_reg.val = @bitCast(r);
}

// pub fn set_alarm(us: u32) void {
//     const Duration = microzig.drivers.time.Duration;
//     const current = time.get_time_since_boot();
//     const target = current.add_duration(Duration.from_us(us));

//     timer.ALARM0.write_raw(@intCast(@intFromEnum(target) & 0xffffffff));
// }

const tree = Tree.create(items, 16 - 1, 2000);
const LCD = olimex_lcd.BufferedLCD(tree.bufferLines);
const TuiImpl = TUI.Impl(tree, &button_masks);

pub fn main() !void {
    Config.read(&Config.values);
    try IO.init();
    // init uart logging
    rp2xxx.uart.init_logger(IO.uart0);

    std.log.info("setup lcd", .{});
    var lcd = LCD.init(IO.i2c_device.i2c_device(), @enumFromInt(0x30));
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
    switch_simulator_interrupt();
    while (true) {
        var events: [8]Event = undefined;
        var ev_idx: u8 = 0;
        // while (cfg_events.len > 0 and ev_idx < events.len) {
        //     events[ev_idx] = cfg_events[0];
        //     cfg_events = cfg_events[1..];
        //     ev_idx += 1;
        // }
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
                .use_simulator => {
                    switch_simulator_interrupt();
                },
                // .save_config => {
                //     switch (ev.pl.tui.button) {
                //         true => {
                //             log.info("config true", .{});
                //             config.write();
                //             time.sleep_ms(100);
                //             log.info("config done", .{});
                //         },
                //         false => {
                //             log.info("config false", .{});
                //         },
                //     }
                // },
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
                // else => {
                //     log.info("Unhandled Event", .{});
                // },
            }
        }
        // gpio.num(25).put(1);
        // time.sleep_ms(100);
        // gpio.num(25).put(0);
        // time.sleep_ms(900);
    }
}
test {
    _ = FlashJournal;
}
