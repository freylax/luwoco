const std = @import("std");
const microzig = @import("microzig");
const hal = microzig.hal;
const time = hal.time;
const Datagram_Device = microzig.drivers.base.Datagram_Device;
const Mutex = hal.mutex.Mutex;
const assert = std.debug.assert;

const CursorType = enum {
    select,
    change,
};

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
        dd: Datagram_Device,
        mx: Mutex,
        buf: [nLines]Line = [_]Line{Line{}} ** nLines, // buffer for writing, protected by mx
        dBuf: [2][Line.len]u8 = .{.{' '} ** Line.len} ** 2, // the actual displayed chars
        dLines: [2]usize = .{ 0, 1 }, // the actual displayed lines
        butOneShot: u4, // set the button bit for one shot buttons
        butLast: u4 = 0, // the last buttons read
        cursorOn: bool = false,
        cursorLine: u16 = 0,
        cursorCol: u8 = 0,
        cursorSavedChar: u8 = ' ',

        pub fn init(dd: Datagram_Device, butOneShot: u4) Self {
            return Self{
                .dd = dd,
                .mx = Mutex{},
                .butOneShot = butOneShot,
            };
        }

        pub fn write(self: *Self, line: usize, pos: usize, str: []const u8) void {
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
        pub fn cursorOff(self: *Self) void {
            defer self.mx.unlock();
            self.mx.lock();
            if (self.cursorOn) {
                // restore the buffer
                self.buf[self.cursorLine].buf[self.cursorCol] = self.cursorSavedChar;
                self.buf[self.cursorLine].stamp_in += 1;
            }
            self.cursorOn = false;
        }
        pub fn cursor(self: *Self, bLine: u16, bCol: u8, _: u16, _: u8, cursorType: CursorType) void {
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
        const WriteError = Datagram_Device.ConnectError || Datagram_Device.WriteError;
        const ReadError = Datagram_Device.ConnectError || Datagram_Device.ReadError;

        pub fn print(self: *Self, lines: [2]u16) WriteError!void {
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
                        try self.write_datagram(0x61, &.{ @intCast(1 - i), @intCast(j), c });
                        time.sleep_ms(20);
                        // std.log.info("send at {d},{d} '{c}'", .{ i, j, c });
                    }
                }
            }
        }

        pub fn read_buttons(self: *Self) ReadError!u4 {
            var buf: [1]u8 = .{0};
            _ = try self.read_datagram(0x05, &buf);
            const but: u4 = @intCast(buf[0] ^ 0x0f);
            const res = but & ~(self.butLast & self.butOneShot);
            self.butLast = but;
            return res;
            // a l o r
            // 1 1 1 0
            // 1 1 0 1
            // 0 1 1 0
            // 0 1 0 0
            // 1 0 1 1  a & ~( l & o)
            // 1 0 0 1
        }

        /// Sends command data to the lcd
        fn write_datagram(self: Self, cmd: u8, argv: []const u8) WriteError!void {
            try self.dd.connect();
            defer self.dd.disconnect();
            try self.dd.writev(&.{ &.{cmd}, argv });
        }
        fn read_datagram(self: Self, cmd: u8, argv: []u8) ReadError!usize {
            try self.dd.connect();
            defer self.dd.disconnect();
            try self.dd.writev(&.{&.{cmd}});
            return try self.dd.read(argv);
        }
    };
}
