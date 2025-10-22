const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;
const testing = std.testing;

const magic_bytes = "fj";

const Ptr = [*]const u8;

fn readBytesAs(comptime T: type, ptr: *Ptr) T {
    const r = mem.bytesToValue(T, ptr.*);
    ptr.* += @sizeOf(T);
    return r;
}

// create flash journal for one sector
pub fn create(
    comptime data_len_type: type, // u8 minimal, this has to be fixed for the usage of the flash
    comptime max_data_size: data_len_type, // the maximal size of data in history
    comptime page_size: usize,
    comptime pages: usize, // has to be sector_size / page_size
    storage: [*]const u8, // used for reading the flash, points to the start of sector
    write_page: *const fn (page_idx: usize, page: []const u8) void,
    erase_sector: *const fn () void,
) type {
    const DLT = data_len_type;

    return struct {
        const Self = @This();
        data: [max_data_size]u8 = .{0} ** max_data_size,
        page: [page_size]u8 = .{0} ** page_size,
        page_idx: usize = 0,
        page_offset: usize = 0, //
        ptr: [*]const u8 = storage,
        data_idx: usize = 0,
        first_write: bool = true,
        invalid_flash_data: bool = true,

        pub fn read_page(self: *Self) void {
            const p = storage + self.page_idx * page_size;
            mem.copyForwards(u8, &self.page, p[0..page_size]);
            // std.log.info("FJ.read_page({d}) at {x}:{x}", .{ self.page_idx, @intFromPtr(p), p[0..50] });
        }

        pub fn read(self: *Self) []const u8 {
            if (self.ptr != storage) {
                // std.log.info("FJ.read already read data in.", .{});
                return &self.data;
            }

            // std.log.info("FJ.read storage at {x}:{x}", .{ @intFromPtr(storage), storage[0..50] });
            // read data in
            // check for the magic bytes
            if (!mem.eql(u8, self.ptr[0..magic_bytes.len], magic_bytes)) {
                // std.log.info("FJ.read no magic bytes found.", .{});
                // no magic bytes found, the zero data will be returned
                return &self.data;
            }
            self.invalid_flash_data = false;
            // std.log.info("FJ.read found magic bytes.", .{});
            self.ptr += magic_bytes.len;
            while (true) {
                var i: usize = 0;
                const size = readBytesAs(DLT, &self.ptr);
                // std.log.info("FJ.read size={d}", .{size});
                if (size == std.math.maxInt(DLT)) {
                    // set the pointer back
                    self.ptr -= @sizeOf(DLT);
                    // std.log.info("FJ.read reached the end.", .{});
                    break;
                }
                i += readBytesAs(DLT, &self.ptr); // skip
                // std.log.info("FJ.read skip={d}", .{i});
                while (i < size) {
                    const chunk_size = readBytesAs(DLT, &self.ptr);
                    // std.log.info("FJ.read chunk_size={d}", .{chunk_size});
                    for (0..chunk_size) |_| {
                        self.data[i] = self.ptr[0];
                        // std.log.info("FJ.read data({d})={x}", .{ i, self.data[i] });
                        i += 1;
                        self.ptr += 1;
                    }
                    if (i < size) {
                        const skip = readBytesAs(DLT, &self.ptr);
                        i += skip;
                        // std.log.info("FJ.read skip={d}", .{skip});
                    }
                }
                // we updated one data record
                self.data_idx += 1;
                // std.log.info("FJ.read data_idx={d}", .{self.data_idx});
            }
            // initialize the page pointers
            const diff = self.ptr - storage;
            self.page_idx = diff / page_size;
            self.page_offset = diff % page_size;
            // std.log.info("FJ.read page_idx={d}", .{self.page_idx});
            // std.log.info("FJ.read page_offset={x}", .{self.page_offset});
            return &self.data;
        }

        // write to page, change page if necessary
        pub fn writeBytes(self: *Self, bytes: []const u8) void {
            if (self.page_idx == pages) {
                // we are full
                return;
            }
            for (0..bytes.len) |i| {
                if (self.page_offset == page_size) {
                    // the page is full, write it
                    if (self.page_idx + 1 < pages) {
                        // overwrap, we do not write the page, data
                        // gets written to the first page instead
                        write_page(self.page_idx, &self.page);
                    }
                    self.page_idx += 1;
                    self.page_offset = 0;
                    if (self.page_idx == pages) {
                        // we are full
                        return;
                    } else {
                        // read the new page in
                        self.read_page();
                    }
                }
                self.page[self.page_offset] = bytes[i];
                self.page_offset += 1;
                self.ptr += 1;
            }
        }

        fn writeAsBytes(self: *Self, v: anytype) void {
            self.writeBytes(mem.asBytes(v));
        }

        pub fn write(self: *Self, data: []const u8) void {
            // std.log.info("FJ.write", .{});
            if (self.ptr == storage) {
                // std.log.info("FJ.read first write without a former read.", .{});
                // first write without a former read,
                // read the chronological data first
                _ = self.read();
                if (self.invalid_flash_data) {
                    erase_sector();
                }
            }
            if (self.first_write) {
                // std.log.info("FJ.write first_write, read page in", .{});
                // read page in,
                self.read_page();
                self.first_write = false;
            }
            // this loop is for the case we reach the end and have to write out
            // data from begining
            for (0..2) |_| {
                if (self.ptr == storage) {
                    // the first write, we have to write the magic bytes first
                    // std.log.info("FJ.write write magic bytes", .{});
                    self.writeBytes(magic_bytes);
                }

                var begin: DLT = 0;
                var skip: DLT = 0;
                // write the len of data
                {
                    const len = @as(DLT, @intCast(data.len));
                    self.writeAsBytes(&len);
                    // std.log.info("FJ.write len={d}", .{len});
                }
                for (0..data.len) |i_| {
                    const i = @as(DLT, @intCast(i_));
                    if (data[i] == self.data[i]) {
                        // data are equal
                        if (skip == 0 and i > 0) {
                            // we have to write the bytes which are not equal
                            // std.log.info("FJ.write nof bytes={d}", .{i - begin});
                            self.writeAsBytes(&(i - begin));
                            self.writeBytes(data[begin..i]);
                            // std.log.info("FJ.write bytes={x}", .{data[begin..i]});
                        }
                        skip += 1;
                    } else {
                        // data are not equal
                        if (skip > 0 or i == 0) {
                            // we change from a skipped range to unskipped one
                            begin = i;
                            self.writeAsBytes(&skip);
                            // std.log.info("FJ.write skip={d}", .{skip});
                            skip = 0;
                        }
                    }
                }
                if (skip == 0) {
                    // we have to write the bytes which are not equal
                    self.writeAsBytes(&(@as(DLT, @intCast(data.len)) - begin));
                    self.writeBytes(data[begin..data.len]);
                    // std.log.info("FJ.write len={d}", .{data.len - begin});
                    // std.log.info("FJ.write bytes={x}", .{data[begin..data.len]});
                } else {
                    self.writeAsBytes(&skip);
                    // std.log.info("FJ.write skip={d}", .{skip});
                }
                if (self.page_idx < pages and self.page_offset > 0) {
                    write_page(self.page_idx, &self.page);
                }
                if (self.page_idx == pages) {
                    // we are full
                    // std.log.info("FJ.write we are full", .{});
                    // make a new start and write out the data
                    erase_sector();
                    self.ptr = storage;
                    self.page_idx = 0;
                    self.page_offset = 0;
                    self.read_page();
                    // reset self.data
                    for (&self.data) |*d| {
                        d.* = 0;
                    }
                    // the for loop will do the write
                } else {
                    // we are not full
                    // std.log.info("FJ.write we are not full", .{});
                    break; // leave the loop
                }
            }
            mem.copyForwards(u8, &self.data, data);
        }
    };
}

fn TestStorage(
    comptime page_size: usize,
    comptime pages: usize,
) type {
    return struct {
        pub const bytes = page_size * pages;
        pub var storage: [bytes]u8 = [_]u8{0xff} ** (bytes);
        pub fn get() [*]const u8 {
            return &storage;
        }
        pub fn set(all_pages_bytes: []const u8) void {
            mem.copyForwards(u8, &storage, all_pages_bytes);
        }
        pub fn write_page(page_idx: usize, page: []const u8) void {
            assert(page.len == page_size);
            assert(page_idx < pages);
            var i = page_idx * page_size;
            for (page) |b| {
                // we simulate the caracteristic of flash program
                // that only ones can be changed to zeros
                storage[i] &= b;
                i += 1;
            }
        }
        pub fn erase_sector() void {
            for (0..pages * page_size) |i| {
                storage[i] = 0xff;
            }
        }
    };
}

test {
    // std.testing.log_level = .info;
    const page_size = 16;
    const pages = 2;

    const storage = comptime TestStorage(page_size, pages);
    storage.set(&.{ 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff });
    const data_0 = "abcd";
    const data_1 = "abed";
    const data_1b = "abed\x00\x00";
    const data_2 = "abcdef";
    const data_3 = "abcDEF";
    const data_4 = "ABCDEF";
    {
        var fj = comptime create(u8, data_0.len, page_size, pages, storage.get(), storage.write_page, storage.erase_sector){};
        fj.write(data_0);
        try testing.expectEqualSlices(
            u8,
            &.{ 'f', 'j', 4, 0, 4, 'a', 'b', 'c', 'd', 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff },
            storage.get()[0..storage.bytes],
        );
        try testing.expectEqualSlices(u8, data_0, fj.read());
    }
    {
        var fj = comptime create(u8, data_0.len, page_size, pages, storage.get(), storage.write_page, storage.erase_sector){};
        try testing.expectEqualSlices(u8, data_0, fj.read());
        fj.write(data_1);
        try testing.expectEqualSlices(
            u8,
            &.{ 'f', 'j', 4, 0, 4, 'a', 'b', 'c', 'd', 4, 2, 1, 'e', 1, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff },
            storage.get()[0..storage.bytes],
        );
    }
    {
        var fj = comptime create(u8, data_2.len, page_size, pages, storage.get(), storage.write_page, storage.erase_sector){};
        try testing.expectEqualSlices(u8, data_1b, fj.read());
        fj.write(data_2);
        try testing.expectEqualSlices(
            u8,
            &.{ 'f', 'j', 4, 0, 4, 'a', 'b', 'c', 'd', 4, 2, 1, 'e', 1, 6, 2, 1, 'c', 1, 2, 'e', 'f', 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff },
            storage.get()[0..storage.bytes],
        );
    }
    {
        var fj = comptime create(u8, data_2.len, page_size, pages, storage.get(), storage.write_page, storage.erase_sector){};
        try testing.expectEqualSlices(u8, data_2, fj.read());
        fj.write(data_3);
        try testing.expectEqualSlices(
            u8,
            &.{ 'f', 'j', 4, 0, 4, 'a', 'b', 'c', 'd', 4, 2, 1, 'e', 1, 6, 2, 1, 'c', 1, 2, 'e', 'f', 6, 3, 3, 'D', 'E', 'F', 0xff, 0xff, 0xff, 0xff },
            storage.get()[0..storage.bytes],
        );
        fj.write(data_4);
        try testing.expectEqualSlices(
            u8,
            &.{ 'f', 'j', 6, 0, 6, 'A', 'B', 'C', 'D', 'E', 'F', 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff },
            storage.get()[0..storage.bytes],
        );
    }
}
