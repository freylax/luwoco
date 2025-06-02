const std = @import("std");
const microzig = @import("microzig");
const olimex_lcd = @import("olimex_lcd.zig");
const rp2xxx = microzig.hal;
const gpio = rp2xxx.gpio;
const i2c = rp2xxx.i2c;
const time = rp2xxx.time;
const I2C_Device = rp2xxx.drivers.I2C_Device;
const Datagram_Device = microzig.drivers.base.Datagram_Device;
const Mutex = rp2xxx.mutex.Mutex;
const multicore = rp2xxx.multicore;
const fifo = multicore.fifo;
const log = std.log;
const assert = std.debug.assert;
// const enabled: ?gpio.Enabled = .enabled;

// const pin_config = rp2xxx.pins.GlobalConfiguration{
//     .GPIO4 = .{
//         .name = "sda",
//         .function = .I2C0_SDA,
//         .slew_rate = .slow,
//         .schmitt_trigger = rp2xxx.gpio.Enabled.enabled,
//     },
//     .GPIO5 = .{
//         .name = "scl",
//         .function = .I2C0_SCL,
//         .slew_rate = .slow,
//         .schmitt_trigger = rp2xxx.gpio.Enabled.enabled,
//     },
// };

const uart = rp2xxx.uart.instance.num(0);
const baud_rate = 115200;
const uart_tx_pin = gpio.num(0);

pub const microzig_options = microzig.Options{
    .log_level = .info,
    .logFn = rp2xxx.uart.log,
};

const led = gpio.num(25);

const i2c0 = i2c.instance.num(0);

const LCD = olimex_lcd.BufferedLCD(2);

var lcd: LCD = undefined;
// var buttons: std.atomic.Value(u8) = std.atomic.Value(u8).init(0);

const Event = enum(u32) {
    None,
    ButtonEsc,
    ButtonDec,
    ButtonInc,
    ButtonRet,
    _,
};

const Mode = enum(u32) { Select, Backlight, _ };

fn core1() void {
    var count: u8 = 0;
    while (true) {
        const ev: Event = @enumFromInt(fifo.read_blocking());
        switch (ev) {
            .ButtonInc => {
                if (count < 98) count += 1;
            },
            .ButtonDec => {
                if (count > 0) count -= 1;
            },
            else => {
                continue;
            },
        }
        const d = std.fmt.digits2(count);
        // led.put(1) ;
        lcd.write(0, 0, &d);
        // time.sleep_ms(250);
        // led.put(0);
        // lcd.write(0, 0, "ooo");
        // time.sleep_ms(250);
    }
}

pub fn main() !void {
    // init uart logging
    uart_tx_pin.set_function(.uart);
    uart.apply(.{
        .baud_rate = baud_rate,
        .clock_config = rp2xxx.clock_config,
    });
    rp2xxx.uart.init_logger(uart);

    std.log.info("Set GPIO pins", .{});

    const scl_pin = gpio.num(5);
    const sda_pin = gpio.num(4);
    inline for (&.{ scl_pin, sda_pin }) |pin| {
        pin.set_slew_rate(.slow);
        pin.set_schmitt_trigger(.enabled);
        pin.set_function(.i2c);
    }

    // pin_config.apply();
    std.log.info("i2c0.apply", .{});
    try i2c0.apply(.{ .clock_config = rp2xxx.clock_config });
    std.log.info("i2c_device", .{});
    var i2c_device = I2C_Device.init(i2c0, @enumFromInt(0x30), null);
    std.log.info("lcd", .{});
    // button 1 and 4 are one shot buttons
    lcd = LCD.init(i2c_device.datagram_device(), 0b1001);
    time.sleep_ms(100);
    led.set_function(.sio);
    led.set_direction(.out);

    multicore.launch_core1(core1);
    log.info("launched_core1", .{});
    lcd.write(0, 0, "Hello Olimex Display!");
    // microzig.cpu.wfi();
    time.sleep_ms(1000);
    while (true) {
        log.info("Print", .{});
        if (lcd.print(.{ 0, 1 })) {} else |err| switch (err) {
            error.IoError => log.err("IoError", .{}),
            error.Timeout => log.err("Timeout", .{}),
            error.DeviceBusy => log.err("DeviceBusy", .{}),
            error.Unsupported => log.err("Unsupported", .{}),
            error.NotConnected => log.err("NotConnected", .{}),
        }
        time.sleep_ms(100);
        const read_buttons = lcd.read_buttons();
        // log.info("clear", .{});
        if (read_buttons) |b| {
            const ev: Event = switch (b) {
                0b0001 => .ButtonRet,
                0b0010 => .ButtonDec,
                0b0100 => .ButtonInc,
                0b1000 => .ButtonEsc,
                else => .None,
            };
            if (ev != .None) fifo.write_blocking(@intFromEnum(ev));
            // buttons.store(b, .monotonic);
        } else |err| switch (err) {
            error.IoError => log.err("IoError", .{}),
            error.Timeout => log.err("Timeout", .{}),
            error.DeviceBusy => log.err("DeviceBusy", .{}),
            error.Unsupported => log.err("Unsupported", .{}),
            error.NotConnected => log.err("NotConnected", .{}),
            error.BufferOverrun => log.err("BufferOverrun", .{}),
        }
        //    time.sleep_ms(100);
    }
}
