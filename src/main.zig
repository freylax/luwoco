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
    // the position of last printable char
    fn last(p: Pos, str: []const u8) Pos {
        var q = p;
        if (str.len > 0) {
            var i: u8 = @intCast(str.len - 1);
            while (i > 0 and (str[i] == ' ' or str[i] == '\n')) {
                i -= 1;
            }
            q.skip(i);
        }
        return q;
    }
    fn skip_(p: Pos, l: u8) Pos {
        var q = p;
        for (0..l) |_| {
            if (q.column == line_end) {
                q.line += 1;
                q.column = 0;
            } else {
                q.column += 1;
            }
        }
        return q;
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
    fn onNewLine(p: *Pos) void {
        if (p.column > 0) {
            p.line += 1;
            p.column = 0;
        }
    }
};

const ItemTag = enum(u2) {
    popup,
    embed,
    label,
    value,
};

const ItemTagLen = @typeInfo(ItemTag).@"enum".fields.len;

const Embed = struct {
    str: []const u8,
    items: []const Item,
};

const Popup = struct {
    str: []const u8,
    items: []const Item,
};

// const Label = struct {
//     str: []const u8,
// };

const Value = struct {
    size: u8,
    ptr: *anyopaque,
    vtable: *const VTable,
    pub const VTable = struct {
        get: *const fn (*anyopaque) []const u8,
    };
    pub inline fn get(v: Value) []const u8 {
        return v.vtable.get(v.ptr);
    }
};

const StrValue = struct {
    str: []const u8 = "Test",
    pub fn value(self: *StrValue) Value {
        return .{
            .size = 4,
            .ptr = self,
            .vtable = &.{
                .get = get,
            },
        };
    }

    fn get(
        ctx: *anyopaque,
    ) []const u8 {
        const self: *StrValue = @ptrCast(@alignCast(ctx));
        return self.str;
    }
};

const Item = union(ItemTag) {
    popup: Popup,
    embed: Embed,
    label: []const u8,
    value: Value,
};
//&[_]u8
//
//
var svalue = StrValue{};

const menu: []const Item = &.{
    // .{ .label = &.{ 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0e, 0x0f, 0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28, 0x29, 0x2a, 0x2b, 0x2e, 0x2f, 0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3a, 0x3b, 0x3e, 0x3f, 0x40, 0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4a, 0x4b, 0x4e, 0x4f, 0x50, 0x51, 0x52, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5a, 0x5b, 0x5e, 0x5f, 0x60, 0x61, 0x62, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6a, 0x6b, 0x6e, 0x6f, 0x70, 0x71, 0x72, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7a, 0x7b, 0x7e, 0x7f, 0x80, 0x81, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89, 0x8a, 0x8b, 0x8e, 0x8f, 0x90, 0x91, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9a, 0x9b, 0x9e, 0x9f, 0xa0, 0xa1, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7, 0xa8, 0xa9, 0xaa, 0xab, 0xae, 0xaf, 0xb0, 0xb1, 0xb2, 0xb3, 0xb4, 0xb5, 0xb6, 0xb7, 0xb8, 0xb9, 0xba, 0xbb, 0xbe, 0xbf, 0xc0, 0xc1, 0xc2, 0xc3, 0xc4, 0xc5, 0xc6, 0xc7, 0xc8, 0xc9, 0xca, 0xcb, 0xce, 0xcf, 0xd0, 0xd1, 0xd2, 0xd3, 0xd4, 0xd5, 0xd6, 0xd7, 0xd8, 0xd9, 0xda, 0xdb, 0xde, 0xdf, 0xe0, 0xe1, 0xe2, 0xe3, 0xe4, 0xe5, 0xe6, 0xe7, 0xe8, 0xe9, 0xea, 0xeb, 0xee, 0xef, 0xf0, 0xf1, 0xf2, 0xf3, 0xf4, 0xf5, 0xf6, 0xf7, 0xf8, 0xf9, 0xfa, 0xfb, 0xfe, 0xff } },
    // .{ .embed = .{
    //     .str = "Embed",
    //     .items = &.{ .{ .label = "aaa\n" }, .{ .label = "bbb" } },
    // } },
    .{ .popup = .{
        .str = " Popup A\n",
        .items = &.{
            .{ .label = "Value:" },
            .{ .value = svalue.value() },
        },
    } },
    .{ .popup = .{
        .str = " Popup B\n",
        .items = &.{
            .{ .label = " Label C\n" },
            .{ .label = " Label D" },
        },
    } },
};
fn treeSize(l: []const Item, count: *[ItemTagLen]u8) void {
    for (l) |i| {
        switch (i) {
            .popup => |p| {
                treeSize(p.items, count);
            },
            .embed => |e| {
                treeSize(e.items, count);
            },
            else => {},
        }
        const tag = @as(ItemTag, i);
        count[@intFromEnum(tag)] += 1;
    }
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

fn advancePosHead(l: []const Item, pos: *Pos) void {
    for (l) |i| {
        switch (i) {
            .popup => |pop| {
                pos.next(pop.str);
            },
            .embed => |emb| {
                pos.next(emb.str);
                advancePos(emb.items, pos);
            },
            .label => |lbl| {
                pos.next(lbl);
            },
            .value => |val| {
                pos.skip(val.size);
            },
        }
    }
}
fn advancePosTail(l: []const Item, pos: *Pos) void {
    for (l) |i| {
        switch (i) {
            .popup => |pop| {
                pos.onNewLine(); // there the popups can go
                advancePos(pop.items, pos);
            },
            else => {},
        }
    }
}
fn advancePos(l: []const Item, pos: *Pos) void {
    advancePosHead(l, pos);
    advancePosTail(l, pos);
}

const bufferLines = calcLines: {
    var pos = Pos{ .line = 0, .column = 0 };
    advancePos(menu, &pos);
    if (pos.column > 0) {
        pos.line += 1;
    }
    break :calcLines pos.line;
};

// const menuSize = treeSize(menu, &treeSizeCounter);
const RtItemTag = enum(u2) {
    section,
    value,
    label,
};

const RtItem = struct {
    tag: RtItemTag,
    pos: Pos,
    ptr: u8, // specific ptr into tag array
    last: Pos, // pos of last printable char
};

const RtSection = struct {
    begin: u8,
    end: u8,
    cursor: u8 = 0, // the current cursor item (down)
    parent: u8 = 0, // parent section (up)
    lines: [2]u8, // displayed lines
};

const RtValue = struct {
    item: u8,
    value: Value,
};

const nrRtSections = nrItems[@intFromEnum(ItemTag.popup)] + nrItems[@intFromEnum(ItemTag.embed)] + 1;
const nrRtValues = nrItems[@intFromEnum(ItemTag.value)];
const nrRtLabels = nrItems[@intFromEnum(ItemTag.label)];
const nrRtItems = nrRtSections + nrRtValues + nrRtLabels;

var items: [nrRtItems]RtItem = undefined;
var sections: [nrRtSections]RtSection = undefined;
var values: [nrRtValues]RtValue = undefined;

const LCD = olimex_lcd.BufferedLCD(bufferLines);

var lcd: LCD = undefined;
const Idx = struct {
    item: u8,
    section: u8,
    value: u8,
};

fn initMenu() void {
    var pos = Pos{ .column = 0, .line = 0 };
    var idx = Idx{ .item = 1, .section = 1, .value = 0 };
    // the root item
    items[0] = .{ .tag = .section, .pos = pos, .ptr = 0, .last = pos };
    sections[0] = .{ .begin = 1, .end = 1 + menu.len, .cursor = 1, .parent = 0, .lines = .{ 0, 1 } };
    initMenuR(menu, &pos, &idx, 0);
}

fn initMenuR(l: []const Item, pos: *Pos, idx: *Idx, parent: u8) void {
    const item_start = idx.item;
    initMenuHead(l, pos, idx, parent);
    initMenuTail(l, pos, idx, item_start);
}

fn initMenuHead(l: []const Item, pos: *Pos, idx: *Idx, parent: u8) void {
    const item_start = idx.item;
    idx.item += @intCast(l.len);
    for (l, item_start..) |i, j| {
        switch (i) {
            .popup => |pop| {
                lcd.write(pos.line, pos.column, pop.str);
                items[j] = .{
                    .tag = .section,
                    .pos = pos.*,
                    .ptr = idx.section,
                    .last = pos.*.last(pop.str),
                };
                sections[idx.section] = .{
                    .begin = 0,
                    .end = 0,
                    .parent = parent,
                    .lines = .{ 0, 0 },
                }; // this will be filled in initMenuTail
                pos.next(pop.str);
                idx.section += 1;
            },
            .embed => |emb| {
                lcd.write(pos.line, pos.column, emb.str);
                items[j] = .{
                    .tag = .section,
                    .pos = pos.*,
                    .ptr = idx.section,
                    .last = pos.*.last(emb.str),
                };
                const line = items[idx.item].pos.line;
                const end: u8 = @intCast(idx.item + emb.items.len);
                sections[idx.section] = .{
                    .begin = idx.item,
                    .end = end,
                    .parent = parent,
                    .cursor = idx.item,
                    .lines = if (end > idx.item and line < items[end - 1].last.line)
                        .{ line, line + 1 }
                    else
                        .{ items[j].pos.line, line },
                };
                pos.next(emb.str);
                const this_section = idx.section;
                idx.section += 1;
                initMenuR(emb.items, pos, idx, this_section); // @intCast(j));
            },
            .label => |lbl| {
                lcd.write(pos.line, pos.column, lbl);
                items[j] = .{
                    .tag = .label,
                    .pos = pos.*,
                    .ptr = 0,
                    .last = pos.*.last(lbl),
                };
                pos.next(lbl);
            },
            .value => |val| {
                const s = "xxxxxxxxxxxxxx";
                lcd.write(pos.line, pos.column, s[0..val.size]);
                items[j] = .{
                    .tag = .value,
                    .pos = pos.*,
                    .ptr = idx.value,
                    .last = pos.*.skip_(val.size - 1),
                };
                pos.skip(val.size);
                values[idx.value] = .{ .item = @intCast(j), .value = val };
                idx.value += 1;
            },
        }
    }
}

fn initMenuTail(l: []const Item, pos: *Pos, idx: *Idx, item_start: u8) void {
    for (l, item_start..) |i, j| {
        switch (i) {
            .popup => |pop| {
                pos.onNewLine();
                const idx_ = idx.*; // get a copy
                initMenuR(pop.items, pos, idx, items[j].ptr); //@intCast(j));
                if (pop.items.len > 0) {
                    const sec: *RtSection = &sections[items[j].ptr];
                    sec.begin = idx_.item;
                    sec.end = @intCast(idx_.item + pop.items.len);
                    sec.cursor = idx_.item;
                    const line = items[sec.begin].pos.line;
                    // test if we have only one line in the section
                    if (line == items[sec.end - 1].pos.line) {
                        // then we show the parent and the section line
                        sec.lines = .{ items[j].pos.line, line };
                    } else {
                        // otherwise the two lines will display the first two lines of the section
                        sec.lines = .{ line, line + 1 };
                    }
                }
            },
            else => {},
        }
    }
}

var curSection: u8 = 0;

fn advanceCursor(dir: enum { left, right, down, up }) void {
    const sec: *RtSection = &sections[curSection];
    const lines = &sec.lines;
    // test if there are members in this section
    if (sec.begin == sec.end) {
        return;
    }
    switch (dir) {
        .left => {
            // first we check if we only have to scroll backwards,
            // this is the case if the cursor item pos is not visible right now
            if (lines[0] > items[sec.cursor].pos.line) {
                // just decrease lines
                lines[1] = lines[0];
                lines[0] -= 1;
            } else {
                // if only one item, do not move cursor
                if (sec.begin + 1 == sec.end) {
                    return;
                }
                const start = sec.cursor; // since we cycle around we need a stop
                while (sec.cursor >= sec.begin) {
                    var line_changed = false;
                    if (sec.cursor == sec.begin) {
                        sec.cursor = sec.end - 1;
                        const li = items[sec.cursor].last.line;
                        if (li != lines[0] and li != lines[1]) {
                            lines[0] = li - 1;
                            lines[1] = li;
                            line_changed = true;
                        }
                    } else {
                        sec.cursor -= 1;
                        if (items[sec.cursor].pos.line < lines[0]) {
                            // decrease lines
                            lines[1] = lines[0];
                            lines[0] -= 1;
                            line_changed = true;
                        }
                    }
                    if (start == sec.cursor or line_changed or switch (items[sec.cursor].tag) {
                        .section, .value => true,
                        else => false,
                    }) break;
                }
            }
        },
        .right => {
            // check if we have to scroll forward
            if (lines[1] < items[sec.cursor].last.line) {
                log.info("right,A", .{});
                // increase lines
                lines[0] = lines[1];
                lines[1] += 1;
            } else {
                log.info("right,B", .{});

                // if only one item, do not move cursor
                if (sec.begin + 1 == sec.end) {
                    return;
                }
                const start = sec.cursor; // since we cycle around we need a stop
                while (sec.cursor < sec.end) {
                    var line_changed = false;
                    if (sec.cursor + 1 == sec.end) {
                        log.info("right,C", .{});
                        sec.cursor = sec.begin;
                        const li = items[sec.cursor].pos.line;
                        if (li != lines[0] and li != lines[1]) {
                            log.info("right,D", .{});
                            lines[0] = li;
                            lines[1] = li + 1;
                            line_changed = true;
                        }
                    } else {
                        log.info("right,E", .{});
                        sec.cursor += 1;
                        if (items[sec.cursor].last.line > lines[1]) {
                            log.info("right,F", .{});
                            // increase lines
                            lines[0] = lines[1];
                            lines[1] += 1;
                            line_changed = true;
                        }
                    }
                    if (start == sec.cursor or line_changed or switch (items[sec.cursor].tag) {
                        .section, .value => true,
                        else => false,
                    }) break;
                }
            }
        },
        .up => {
            if (curSection > 0) {
                curSection = sec.parent;
            }
        },
        .down => {
            switch (items[sec.cursor].tag) {
                .section => {
                    curSection = items[sec.cursor].ptr;
                },
                else => {},
            }
        },
    }
}

fn buttonEvent(ev: Event) void {
    switch (ev) {
        .ButtonInc, .ButtonDec, .ButtonEsc, .ButtonRet => {
            advanceCursor(switch (ev) {
                .ButtonInc => .right,
                .ButtonDec => .left,
                .ButtonEsc => .up,
                .ButtonRet => .down,
                else => .up,
            });
            const sec: *RtSection = &sections[curSection];
            const cItem = items[sec.cursor];
            log.info("cursor item:{d} is at line:{d},column:{d}", .{ sec.cursor, cItem.pos.line, cItem.pos.column });
            if (switch (cItem.tag) {
                .section, .value => true,
                else => false,
            }) {
                lcd.cursor(cItem.pos.line, cItem.pos.column, cItem.last.line, cItem.last.column);
            } else {
                // log.info("set cursor off", .{});
                lcd.cursorOff();
            }
        },

        else => {
            // continue;
        },
    }
}

fn core1() void {
    while (true) {
        const ev: Event = @enumFromInt(fifo.read_blocking());
        buttonEvent(ev);
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
    time.sleep_ms(1000); // we need some time after boot for i2c to become ready, otherwise
    //                      unsupported will be thrown
    // multicore.launch_core1(core1);
    // log.info("launched_core1", .{});
    // lcd.write(0, 0, "Olimex Display");
    // if (lcd.print(.{ 0, 1 })) {
    //     // log.info("print", .{});
    // } else |err| switch (err) {
    //     error.IoError => log.err("IoError", .{}),
    //     error.Timeout => log.err("Timeout", .{}),
    //     error.DeviceBusy => log.err("DeviceBusy", .{}),
    //     error.Unsupported => log.err("Unsupported", .{}),
    //     error.NotConnected => log.err("NotConnected", .{}),
    // }

    // const d = std.fmt.digits2(menuSize);
    // lcd.write(0, 1, &d);
    // microzig.cpu.wfi();
    //
    // log.info("items.len:{d}, sections.len:{d}", .{ items.len, sections.len });
    // log.info("initMenu()", .{});
    initMenu();
    // log.info("initMenu done", .{});
    // log.info("menu:\n{any}", .{menu});
    for (items, 0..) |i, j| {
        log.info("items[{d}]:\n{any}", .{ j, i });
    }
    for (sections, 0..) |s, j| {
        log.info("sections[{d}]:\n{any}", .{ j, s });
    }
    for (values, 0..) |v, j| {
        log.info("values[{d}]: item={d}, size={d}, val={s}", .{ j, v.item, v.value.size, v.value.get() });
    }
    lcd.cursor(0, 0, 0, 0);
    time.sleep_ms(100);
    var changed = true;
    while (true) {
        const sec: *RtSection = &sections[curSection];
        const lines = &sec.lines;
        // iterate over the values and write those which are
        // in the current display area
        for (values) |rval| {
            const item: *RtItem = &items[rval.item];
            if ((item.pos.line <= lines[0] and lines[0] <= item.last.line) or (item.pos.line <= lines[1] and lines[1] <= item.last.line))
                lcd.write(item.pos.line, item.pos.column, rval.value.get());
        }

        // log.info("Print", .{});
        // if (changed) {
        //     log.info("curSection:{d}, lines:{d},{d} ,cursor:{d}", .{ curSection, lines[0], lines[1], sec.cursor });
        // }
        changed = false;
        if (lcd.print(lines.*)) {
            // log.info("print", .{});
        } else |err| switch (err) {
            error.IoError => log.err("IoError", .{}),
            error.Timeout => log.err("Timeout", .{}),
            error.DeviceBusy => log.err("DeviceBusy", .{}),
            error.Unsupported => log.err("Unsupported", .{}),
            error.NotConnected => log.err("NotConnected", .{}),
        }
        time.sleep_ms(100);
        // time.sleep_ms(2000);
        const read_buttons = lcd.read_buttons();
        // log.info("clear", .{});
        if (read_buttons) |b| {
            // log.info("button:{x}", .{b});
            const ev: Event = switch (b) {
                0b0001 => .ButtonEsc,
                0b0010 => .ButtonDec,
                0b0100 => .ButtonInc,
                0b1000 => .ButtonRet,
                else => .None,
            };
            if (ev != .None) {
                // fifo.write_blocking(@intFromEnum(ev));
                buttonEvent(ev);
                changed = true;
            }
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
