const std = @import("std");
const microzig = @import("microzig");
const peripherals = microzig.chip.peripherals;
const olimex_lcd = @import("olimex_lcd.zig");
const Drive = @import("Drive.zig");
const Relais = @import("Relais.zig");
const IntrButton = @import("IntrButton.zig");
const PositionSensor = @import("PositionSensor.zig");
const Buttons = @import("tui/Buttons.zig");
const Tree = @import("tui/Tree.zig");
const TUI = @import("TUI.zig");
const IO = @import("IO.zig");

const Item = Tree.Item;
const values = @import("tui/values.zig");
const IntValue = values.IntValue;
const RefPushButton = values.RefPushButton;
const BulbValue = values.BulbValue;

const rp2xxx = microzig.hal;
const gpio = rp2xxx.gpio;
const interrupt = microzig.cpu.interrupt;
const i2c = rp2xxx.i2c;
const time = rp2xxx.time;
const I2C_Device = rp2xxx.drivers.I2C_Device;
const GPIO_Device = rp2xxx.drivers.GPIO_Device;
const Datagram_Device = microzig.drivers.base.Datagram_Device;
const Mutex = rp2xxx.mutex.Mutex;
const multicore = rp2xxx.multicore;
const fifo = multicore.fifo;
const log = std.log;
const assert = std.debug.assert;

const uart = rp2xxx.uart.instance.num(0);
const baud_rate = 115200;
const uart_tx_pin = gpio.num(0);

const timer = peripherals.TIMER;
const timer_irq = .TIMER_IRQ_0;

pub const microzig_options = microzig.Options{
    .log_level = .info,
    .logFn = rp2xxx.uart.log,
    .interrupts = .{
        .TIMER_IRQ_0 = .{ .c = timer_interrupt },
        .IO_IRQ_BANK0 = .{ .c = gpio_handler },
    },
};

const led = gpio.num(25);

const i2c0 = i2c.instance.num(0);

const EventId = enum(u16) {
    Setup,
    BackLight,
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
};

const Event = struct {
    id: EventId,
    pl: union(EventTag) {
        tui: TUI.Event.PayLoad,
    },
};

const BS = TUI.ButtonSemantics;

const button1: u8 = 0b0001;
const button2: u8 = 0b0010;
const button3: u8 = 0b0100;
const button4: u8 = 0b1000;

const button_masks = blk: {
    const l = TUI.ButtonSemanticsLen;
    var a = [_]u8{0} ** l;
    a[@intFromEnum(BS.escape)] = button1;
    a[@intFromEnum(BS.left)] = button2;
    a[@intFromEnum(BS.right)] = button3;
    a[@intFromEnum(BS.activate)] = button4;
    break :blk a;
};

var io: IO = .{};

var back_light = IntValue{ .min = 0, .max = 255, .val = 0, .id = EventId.BackLight.id() };

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

const items: []const Item = &.{
    .{
        .popup = .{
            .id = EventId.Setup.id(),
            .str = " Setup\n",
            .items = &.{
                .{ .label = "Backlight:" },
                .{ .value = back_light.value() },
            },
        },
    },
    .{ .popup = .{
        .str = " Test Drive X\n",
        .items = &.{
            .{ .label = "    " },
            .{ .label = " X+" },
            .{ .value = pb_dx_dir_a.value(.{ .db = button3 }) },
            .{ .label = " X-" },
            .{ .value = pb_dx_dir_b.value(.{ .db = button4 }) },
        },
    } },
    .{ .popup = .{
        .str = " Test Drive y\n",
        .items = &.{
            .{ .label = "    " },
            .{ .label = " y+" },
            .{ .value = pb_dy_dir_a.value(.{ .db = button3 }) },
            .{ .label = " y-" },
            .{ .value = pb_dy_dir_b.value(.{ .db = button4 }) },
        },
    } },

    .{ .popup = .{
        .str = " Relais Test\n",
        .items = &.{
            .{ .label = "    " },
            .{ .label = " A " },
            .{ .value = pb_relais_a.value(.{ .db = button3 }) },
            .{ .label = " B " },
            .{ .value = pb_relais_b.value(.{ .db = button4 }) },
        },
    } },

    .{ .popup = .{
        .str = " Input Test pos_x\n",
        .items = &.{
            .{ .label = "pos:" },
            .{ .value = IO.pos_x_pos.value() },
            .{ .label = " min:" },
            .{ .value = IO.pos_x_min.value() },
            .{ .label = " max:" },
            .{ .value = IO.pos_x_max.value() },
        },
    } },

    .{
        .popup = .{
            .str = " Characters\n",
            .items = &.{
                .{
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
                },
            },
        },
    },
};

fn timer_interrupt() callconv(.c) void {
    const cs = microzig.interrupt.enter_critical_section();
    defer cs.leave();
    // input_a.val = if (input_a.val) false else true;

    timer.INTR.modify(.{ .ALARM_0 = 1 });

    set_alarm(1_000_000);
}

fn gpio_handler() callconv(.C) void {
    // Acknowledge/clear the interrupt. With an edge-triggered interrupt,
    //  when missing the acknowledge, the interrupt triggers repeatedly forever
    // We're "listening" for falling-edge events on pin 18
    // Search for "INTR0 Register" in the rp2040 datasheet
    // You can also read this register to determine which events have triggered
    // Note: This line is deceptive. It acknowledges every outstanding GPIO event on INTR2
    //     because modify is implemented as a read and then a write, and other bits will be 1 if they are active

    // const M = PositionSensor.Masks;
    // const s = try io.pos_x.state();
    // if(PositionSensor.Masks.test(.pos,s)) {
    //   peripherals.IO_BANK0.INTR2.modify(.{ .GPIO16_EDGE_HIGH = 1 });
    //   pos_x_pos.val=true;
    // } else {
    //   pos_x_pos.val=false;
    // }
    //  if(M.min.test(s)) {
    //   peripherals.IO_BANK0.INTR2.modify(.{ .GPIO17_EDGE_HIGH = 1 });
    //   pos_x_min.val=true;
    // } else {
    //   pos_x_min.val=false;
    // }
    //  if(M.max.test(s)) {
    //   peripherals.IO_BANK0.INTR2.modify(.{ .GPIO18_EDGE_HIGH = 1 });
    //   pos_x_max.val=true;
    // } else {
    //   pos_x_max.val=false;
    // }

}

pub fn set_alarm(us: u32) void {
    const Duration = microzig.drivers.time.Duration;
    const current = time.get_time_since_boot();
    const target = current.add_duration(Duration.from_us(us));

    timer.ALARM0.write_raw(@intCast(@intFromEnum(target) & 0xffffffff));
}

const tree = Tree.create(items, 16 - 1);
const LCD = olimex_lcd.BufferedLCD(tree.bufferLines);
const TuiImpl = TUI.Impl(tree, &button_masks);

pub fn main() !void {
    // init uart logging
    uart_tx_pin.set_function(.uart);
    uart.apply(.{
        .baud_rate = baud_rate,
        .clock_config = rp2xxx.clock_config,
    });
    rp2xxx.uart.init_logger(uart);

    std.log.info("Set GPIO pins", .{});

    IO.init();

    const scl_pin = gpio.num(5);
    const sda_pin = gpio.num(4);
    inline for (&.{ scl_pin, sda_pin }) |pin| {
        pin.set_slew_rate(.slow);
        pin.set_schmitt_trigger(.enabled);
        pin.set_function(.i2c);
    }

    std.log.info("i2c0.apply", .{});
    try i2c0.apply(.{ .clock_config = rp2xxx.clock_config });
    std.log.info("i2c_device", .{});
    var i2c_device = I2C_Device.init(i2c0, @enumFromInt(0x30), null);
    std.log.info("lcd", .{});
    var lcd = LCD.init(i2c_device.datagram_device());
    var display = lcd.display();
    var buttons = lcd.buttons();
    var tuiImpl = TuiImpl.init(display);
    var tui = tuiImpl.tui();
    time.sleep_ms(100);

    try IO.begin();
    // interrupt set enable register
    // peripherals.PPB.NVIC_ISER.modify(.{
    //     .SETENA = 1 << 13, // 13 is IO_IRQ_BANK0
    // });

    // peripherals.IO_BANK0.PROC0_INTE2.modify(.{
    //     .GPIO16_EDGE_HIGH = 1,
    //     .GPIO17_EDGE_HIGH = 1,
    //     .GPIO18_EDGE_HIGH = 1,
    // });

    led.set_function(.sio);
    led.set_direction(.out);

    time.sleep_ms(1000); // we need some time after boot for i2c to become ready, otherwise

    // set_alarm(1_000_000);

    // timer.INTE.toggle(.{ .ALARM_0 = 1 });

    // interrupt.enable(timer_irq);

    // Enable machine external interrupts on RISC-V
    // if (rp2xxx.compatibility.arch == .riscv) {
    // microzig.cpu.interrupt.core.enable(.MachineExternal);
    // }

    // microzig.cpu.interrupt.enable_interrupts();

    //                      unsupported will be thrown

    display.cursor(0, 0, 0, 0, .select);
    time.sleep_ms(100);
    while (true) {
        var events: [8]Event = undefined;
        var ev_idx: u8 = 0;
        tui.writeValues();
        if (tui.print()) {} else |_| {}
        time.sleep_ms(100);
        const read_buttons = buttons.read();
        if (read_buttons) |b| {
            for (tui.buttonEvent(b)) |ev| {
                events[ev_idx] = .{ .id = @enumFromInt(ev.id), .pl = .{ .tui = ev.pl } };
                ev_idx += 1;
            }
        } else |_| {}
        if (lcd.lastError) |e| {
            switch (e) {
                error.IoError => log.err("IoError", .{}),
                error.Timeout => log.err("Timeout", .{}),
                error.DeviceBusy => log.err("DeviceBusy", .{}),
                error.Unsupported => log.err("Unsupported", .{}),
                error.NotConnected => log.err("NotConnected", .{}),
                error.BufferOverrun => log.err("BufferOverrun", .{}),
            }
            lcd.lastError = null;
        }
        for (events[0..ev_idx]) |ev| {
            switch (ev.id) {
                .Setup => {
                    switch (ev.pl.tui.section) {
                        .enter => {
                            log.info("Enter Setup Event", .{});
                        },
                        .leave => {
                            log.info("Leave Setup Event", .{});
                        },
                    }
                },
                .BackLight => {
                    _ = lcd.setBackLight(ev.pl.tui.value);
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
                // else => {
                //     log.info("Unhandled Event", .{});
                // },
            }
        }
    }
}
