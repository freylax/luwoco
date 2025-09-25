const std = @import("std");
const microzig = @import("microzig");
const hal = microzig.hal;
const time = hal.time;
const I2C_Device = microzig.drivers.base.I2C_Device;
const Mutex = hal.mutex.Mutex;
const assert = std.debug.assert;
const Display = @import("tui/Display.zig");
const Buttons = @import("tui/Buttons.zig");

pub const line_len = 16;
pub fn BufferedLCD(comptime NrOfLines: comptime_int) type {
    assert(NrOfLines >= 2);
    const Line = struct {
        const len = line_len;
        buf: [len]u8 = [_]u8{' '} ** len,
        stamp_in: u8 = 0,
        stamp_out: u8 = 0,
    };
    return struct {
        const Self = @This();
        const nLines = NrOfLines;
        dev: I2C_Device,
        addr: I2C_Device.Address,
        mx: Mutex,
        buf: [nLines]Line = [_]Line{Line{}} ** nLines, // buffer for writing, protected by mx
        dBuf: [2][Line.len]u8 = .{.{' '} ** Line.len} ** 2, // the actual displayed chars
        dLines: [2]usize = .{ 0, 1 }, // the actual displayed lines
        cursorOn: bool = false,
        cursorLine: u16 = 0,
        cursorCol: u8 = 0,
        cursorSavedChar: u8 = ' ',
        lastError: ?Error = null,
        pub fn display(self: *Self) Display {
            return .{
                .lines = 2,
                .columns = NrOfLines,
                .ptr = self,
                .vtable = &.{
                    .write = write,
                    .cursorOff = cursorOff,
                    .cursor = cursor,
                    .print = print,
                },
            };
        }

        pub fn buttons(self: *Self) Buttons {
            return .{
                .ptr = self,
                .vtable = &.{
                    .read = readButtons,
                },
            };
        }

        pub fn init(dev: I2C_Device, addr: I2C_Device.Address) Self {
            return Self{
                .dev = dev,
                .addr = addr,
                .mx = Mutex{},
            };
        }

        pub fn write(ctx: *anyopaque, line: u16, pos: u8, str: []const u8) void {
            const self: *Self = @ptrCast(@alignCast(ctx));
            if (line >= nLines) return;
            var modified: bool = false;
            var l = line;
            var p = pos;
            defer self.mx.unlock();
            self.mx.lock();
            for (str) |c| {
                if (c == '\n' or p >= Line.len) {
                    p = 0;
                    if (modified) {
                        self.buf[l].stamp_in += 1;
                        modified = false;
                    }
                    l += 1;
                    if (l >= nLines) return;
                    if (c == '\n') continue;
                }
                if (self.cursorOn and l == self.cursorLine and p == self.cursorCol) {
                    self.cursorSavedChar = c;
                } else if (self.buf[l].buf[p] != c) {
                    self.buf[l].buf[p] = c;
                    modified = true;
                }
                p += 1;
            }
            if (modified) {
                self.buf[l].stamp_in += 1;
            }
        }
        pub fn cursorOff(ctx: *anyopaque) void {
            const self: *Self = @ptrCast(@alignCast(ctx));
            defer self.mx.unlock();
            self.mx.lock();
            if (self.cursorOn) {
                // restore the buffer
                self.buf[self.cursorLine].buf[self.cursorCol] = self.cursorSavedChar;
                self.buf[self.cursorLine].stamp_in += 1;
            }
            self.cursorOn = false;
        }
        pub fn cursor(ctx: *anyopaque, bLine: u16, bCol: u8, _: u16, _: u8, cursorType: Display.CursorType) void {
            const self: *Self = @ptrCast(@alignCast(ctx));
            defer self.mx.unlock();
            self.mx.lock();
            //inspect the buffer
            // if (bLine == self.cursorLine and bCol == self.cursorCol) return;
            if (self.cursorOn and (bLine != self.cursorLine or bCol != self.cursorCol)) {
                // std.log.info("restore cursor at {d},{d} to char '{c}'", .{ self.cursorLine, self.cursorCol, self.cursorSavedChar });
                // restore the buffer of the current cursor position
                self.buf[self.cursorLine].buf[self.cursorCol] = self.cursorSavedChar;
                self.buf[self.cursorLine].stamp_in += 1;
            }

            if (bLine < nLines and bCol < Line.len) {
                self.cursorOn = true;
                // var fw = true;
                // const fw = true;
                // if (self.buf[line].buf[pos] == ' ') {
                //     self.cursorLine = line;
                //     self.cursorPos = pos;
                // } else if (pos > 0 and self.buf[line].buf[pos - 1] == ' ') {
                //     self.cursorLine = line;
                //     self.cursorPos = pos - 1;
                // } else if (pos + len < Line.len and self.buf[line].buf[pos + len] == ' ') {
                //     self.cursorLine = line;
                //     self.cursorPos = pos + len;
                //     fw = false;
                // } else if (pos + len - 1 < Line.len and self.buf[line].buf[pos + len - 1] == ' ') {
                //     self.cursorLine = line;
                //     self.cursorPos = pos + len - 1;
                //     fw = false;
                // } else {
                const cursorChar: u8 = switch (cursorType) {
                    .select => 0x7e, // ->
                    .change => '|', // |
                };
                if (self.buf[self.cursorLine].buf[self.cursorCol] != cursorChar) {
                    self.cursorLine = bLine;
                    self.cursorCol = bCol;
                    self.cursorSavedChar = self.buf[self.cursorLine].buf[self.cursorCol];
                    self.buf[self.cursorLine].buf[self.cursorCol] = cursorChar;
                    // if (fw) '}' + 1 else '}' + 2;
                    self.buf[self.cursorLine].stamp_in += 1;
                    // std.log.info("set lcd cursor at {d},{d},{d},'{c}'", .{ self.cursorLine, self.cursorCol, self.buf[self.cursorLine].stamp_in, self.buf[self.cursorLine].buf[self.cursorCol] });
                    // std.log.info("set lcd cursor buf {s}", .{&self.buf[self.cursorLine].buf});
                }
            } else {
                self.cursorOn = false;
            }
        }
        const Error = I2C_Device.InterfaceError;
        pub fn print(ctx: *anyopaque, lines: []const u16) ?void {
            const self: *Self = @ptrCast(@alignCast(ctx));
            // insert the chars to print/update, all other are zero
            var toPrint: [2][Line.len]u8 = .{.{0} ** Line.len} ** 2;
            {
                defer self.mx.unlock();
                self.mx.lock();
                for (lines, 0..) |l, i| {
                    if (l >= nLines) continue;
                    // check if no modification did happend
                    const bufl = &self.buf[l];
                    if (l == self.dLines[i] and bufl.stamp_in == bufl.stamp_out) continue;
                    // std.log.info(
                    // "stamps for line {d}: in {d}, out {d}, buf '{s}', dbuf '{s}'",
                    // .{ l, bufl.stamp_in, bufl.stamp_out, &bufl.buf, &self.dBuf[i] },
                    // );
                    for (0..Line.len) |j| {
                        // check if chars differ
                        const c = bufl.buf[j];
                        if (c != self.dBuf[i][j]) {
                            toPrint[i][j] = c;
                            self.dBuf[i][j] = c;
                        }
                    }
                    self.dLines[i] = l;
                    bufl.stamp_out = bufl.stamp_in;
                }
                // std.log.info("lcd cursor at {d},{d},{any}", .{ self.cursorLine, self.cursorCol, self.cursorOn });

                // mutex gets released here
            }
            // now the time consuming communication with the display
            for (0..2) |i| {
                for (0..Line.len) |j| {
                    const c = toPrint[i][j];
                    if (c != 0) {
                        self.write_datagram(0x61, &.{ @intCast(1 - i), @intCast(j), c }) catch |e| {
                            self.lastError = e;
                            return null;
                        };
                        time.sleep_ms(20);
                        // std.log.info("send at {d},{d} '{c}'", .{ i, j, c });
                    }
                }
            }
        }

        pub fn readButtons(ctx: *anyopaque) ?u8 {
            const self: *Self = @ptrCast(@alignCast(ctx));
            var buf: [1]u8 = .{0};
            _ = self.read_datagram(0x05, &buf) catch |e| {
                self.lastError = e;
                return null;
            };
            return buf[0] ^ 0x0f;
        }

        pub fn setBackLight(self: *Self, val: u8) ?void {
            self.write_datagram(0x62, &.{val}) catch |e| {
                self.lastError = e;
                return null;
            };
            time.sleep_ms(20);
        }

        /// Sends command data to the lcd
        fn write_datagram(self: Self, cmd: u8, argv: []const u8) Error!void {
            try self.dev.writev(self.addr, &.{ &.{cmd}, argv });
        }
        fn read_datagram(self: Self, cmd: u8, argv: []u8) Error!usize {
            try self.dev.writev(self.addr, &.{&.{cmd}});
            return try self.dev.read(self.addr, argv);
        }
    };
}
