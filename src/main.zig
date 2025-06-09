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

// var buttons: std.atomic.Value(u8) = std.atomic.Value(u8).init(0);

const Event = enum(u32) {
    None,
    ButtonEsc,
    ButtonDec,
    ButtonInc,
    ButtonRet,
    _,
};

const line_len = olimex_lcd.line_len;
const line_end = line_len - 1;

const Pos = struct {
    line: u8,
    column: u5,
    fn next(p: *Pos, str: []const u8) void {
        for (str) |c| {
            switch (c) {
                '\n' => {
                    p.newLine();
                },
                else => {
                    if (p.column == line_end) {
                        p.newLine();
                    } else {
                        p.column += 1;
                    }
                },
            }
        }
    }
    fn skip(p: *Pos, l: u8) void {
        for (0..l) |_| {
            if (p.column == line_end) {
                p.newLine();
            } else {
                p.column += 1;
            }
        }
    }
    fn newLine(p: *Pos) void {
        p.line += 1;
        p.column = 0;
    }
};

const ItemTag = enum(u2) {
    column,
    line,
    label,
    value,
};

const ItemTagLen = @typeInfo(ItemTag).@"enum".fields.len;

const Column = struct {
    str: []const u8,
    items: []const Item,
};

const Line = struct {
    str: []const u8,
    items: []const Item,
};

const Label = struct {
    str: []const u8,
};

const Value = struct {
    size: u8,
};

const Item = union(ItemTag) {
    column: Column,
    line: Line,
    label: Label,
    value: Value,
};

const menu: Item =
    .{
        .column = .{
            .str = "Worm Cook",
            .items = &.{.{ .line = Line{
                .str = "Operation",
                .items = &.{.{ .value = Value{ .size = 3 } }},
            } }},
            // .{
            //     .str = "Ranges",
            //     .sib = &.{
            //         .{ .str = "min x" },
            //         .{ .str = "max x" },
            //     },
            // },
        },
    };
fn treeSize(i: Item, count: *[ItemTagLen]u8) void {
    switch (i) {
        .column => |col| {
            for (col.items) |j| {
                treeSize(j, count);
            }
        },
        .line => |line| {
            for (line.items) |j| {
                treeSize(j, count);
            }
        },
        else => {},
    }
    const tag = @as(ItemTag, i);
    count[@intFromEnum(tag)] += 1;
}

const nrItems = calcTreeSize: {
    var counter = [_]u8{0} ** ItemTagLen;
    treeSize(menu, &counter);
    break :calcTreeSize counter;
};

const totalNrItems = sumUp: {
    var i = 0;
    for (0..ItemTagLen) |j| {
        i += nrItems[j];
    }
    break :sumUp i;
};

fn advancePos(i: Item, p: *Pos, use_lbl: bool, use_items: bool) void {
    switch (i) {
        .column => |c| {
            if (use_lbl) {
                p.next(c.str);
            }
            if (use_items) {
                for (c.items) |j| {
                    advancePos(j, p, true, false);
                    p.newLine();
                }
                for (c.items) |j| {
                    advancePos(j, p, false, true);
                }
            }
        },
        .line => |l| {
            if (use_lbl) {
                p.next(l.str);
            }
            if (use_items) {
                for (l.items) |j| {
                    advancePos(j, p, true, true);
                }
            }
        },
        .label => |l| {
            if (use_lbl) p.next(l.str);
        },
        .value => |v| {
            if (use_lbl) p.skip(v.size);
        },
    }
}

const bufferLines = calcLines: {
    var pos = Pos{ .line = 0, .column = 0 };
    advancePos(menu, &pos, true, true);
    if (pos.column > 0) {
        pos.line += 1;
    }
    break :calcLines pos.line;
};

// const menuSize = treeSize(menu, &treeSizeCounter);
const RtItemTag = enum(u2) {
    section,
    value,
};

const RtItem = struct {
    tag: RtItemTag,
    pos: Pos,
    parent: u8,
    ptr: u8, // specific ptr into tag array
};

const RtSection = struct {
    begin: u8,
    end: u8,
};

const nrRtSections = nrItems[@intFromEnum(ItemTag.column)] + nrItems[@intFromEnum(ItemTag.line)];
const nrRtValues = nrItems[@intFromEnum(ItemTag.value)];
const nrRtItems = nrRtSections + nrRtValues;

var rtItems: [nrRtItems]RtItem = undefined;
var rtSections: [nrRtSections]RtSection = undefined;

const LCD = olimex_lcd.BufferedLCD(bufferLines);

var lcd: LCD = undefined;

fn initMenu(it: Item, idx: u8, sidx: u8) u8 {
    var si: u8 = @intCast(sidx + it.sib.len);
    for (it.sib, 1..) |s, i| {
        si += initMenu(s, @intCast(idx + i), si);
    }
    if (it.sib.len > 0) {
        const r = &rmenu[idx];
        r.sib_b = idx + 1;
        r.sib_e = @intCast(idx + 1 + it.sib.len);
    }
    lcd.write(idx, 2, it.str);
    return si;
}

var dispLines: [2]u8 = .{ 0, 1 };

fn core1() void {
    // var count: u8 = 0;
    // var menu: Menu = .Main;
    while (true) {
        const ev: Event = @enumFromInt(fifo.read_blocking());
        switch (ev) {
            .ButtonInc => {
                if (dispLines[1] < menuSize - 1) {
                    dispLines[0] += 1;
                    dispLines[1] += 1;
                }
            },
            .ButtonDec => {
                if (dispLines[0] > 0) {
                    dispLines[0] -= 1;
                    dispLines[1] -= 1;
                }
            },
            else => {
                continue;
            },
        }
        // const m = rmenu[dispLines[0]];
        // const d0 = std.fmt.digits2(m.sib_b);
        // const d1 = std.fmt.digits2(m.sib_e);
        // led.put(1) ;
        // lcd.write(dispLines[0], 14, &d0);
        // lcd.write(dispLines[1], 14, &d1);

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
    // lcd.write(0, 0, "Olimex Display");

    // const d = std.fmt.digits2(menuSize);
    // lcd.write(0, 1, &d);
    // microzig.cpu.wfi();
    _ = initMenu(menu, 0, 1);
    for (rmenu, 0..) |m, i| {
        log.info("rmenu[{d}]: {d},{d}", .{ i, m.sib_b, m.sib_e });
    }
    time.sleep_ms(1000);
    while (true) {
        // log.info("Print", .{});
        if (lcd.print(dispLines)) {} else |err| switch (err) {
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
