const std = @import("std");
const microzig = @import("microzig");
const hal = microzig.hal;
const time = hal.time;
const Datagram_Device = microzig.drivers.base.Datagram_Device;
const Mutex = hal.mutex.Mutex;
const assert = std.debug.assert;

pub fn BufferedLCD(comptime NrOfLines: comptime_int) type {
    assert(NrOfLines >= 2);
    const Line = struct {
        const len = 16;
        buf: [len]u8 = [_]u8{' '} ** len,
        stamp: u32 = 0,
    };
    return struct {
        const Self = @This();
        const nLines = NrOfLines;
        dd: Datagram_Device,
        mx: Mutex,
        buf: [nLines]Line = [_]Line{Line{}} ** nLines, // buffer for writing, protected by mx
        dBuf: [2]Line = [_]Line{Line{}} ** 2, // the actual displayed chars
        dLines: [2]usize = .{ 0, 1 }, // the actual displayed lines
        butOneShot: u4, // set the button bit for one shot buttons
        butLast: u4 = 0, // the last buttons read

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
                        self.buf[l].stamp += 1;
                        modified = false;
                    }
                    l += 1;
                    if (l >= nLines) return;
                    if (c == '\n') continue;
                }
                if (self.buf[l].buf[p] != c) {
                    self.buf[l].buf[p] = c;
                    modified = true;
                }
                p += 1;
            }
            if (modified) {
                self.buf[l].stamp += 1;
            }
        }
        const WriteError = Datagram_Device.ConnectError || Datagram_Device.WriteError;
        const ReadError = Datagram_Device.ConnectError || Datagram_Device.ReadError;

        pub fn print(self: *Self, lines: [2]usize) WriteError!void {
            // insert the chars to print/update, all other are zero
            var toPrint: [2][Line.len]u8 = .{.{0} ** Line.len} ** 2;
            {
                defer self.mx.unlock();
                self.mx.lock();
                for (lines, 0..) |l, i| {
                    if (l >= nLines) continue;
                    // check if no modification did happend
                    if (l == self.dLines[i] and self.buf[l].stamp == self.dBuf[i].stamp) continue;
                    for (0..Line.len) |j| {
                        // check if chars differ
                        const c = self.buf[l].buf[j];
                        if (c != self.dBuf[i].buf[j]) {
                            toPrint[i][j] = c;
                            self.dBuf[i].buf[j] = c;
                        }
                    }
                    self.dLines[i] = l;
                    self.dBuf[i].stamp = self.buf[l].stamp;
                }
                // mutex gets released here
            }
            // now the time consuming communication with the display
            for (0..2) |i| {
                for (0..Line.len) |j| {
                    const c = toPrint[i][j];
                    if (c != 0) {
                        try self.write_datagram(0x61, &.{ @intCast(1 - i), @intCast(j), c });
                        time.sleep_ms(20);
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
