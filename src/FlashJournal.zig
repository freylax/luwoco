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

pub fn create(
    comptime data_len_type: type, // u8 minimal, this has to be fixed
    comptime data_size: data_len_type,
    comptime max_data_size: data_len_type, // the maximal size of data in history
    comptime page_size: usize,
    comptime pages: usize,
    storage: [*]const u8, // used for reading the flash
    write_page: *const fn (page_idx: usize, page: []const u8) void,
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

        pub fn read(self: *Self) []const u8 {
            if (self.ptr != storage) {
                return &self.data;
            }
            // read data in
            // check for the magic bytes
            if (!mem.eql(u8, self.ptr[0..magic_bytes.len], magic_bytes)) {
                // no magic bytes found, the zero data will be returned
                return &self.data;
            }
            self.ptr += magic_bytes.len;
            while (self.ptr[0] != 0) {
                var i: usize = 0;
                const size = readBytesAs(DLT, &self.ptr);
                i += readBytesAs(DLT, &self.ptr); // skip
                while (i < size) {
                    const chunk_size = readBytesAs(DLT, &self.ptr);
                    for (0..chunk_size) |_| {
                        self.data[i] = self.ptr[0];
                        i += 1;
                        self.ptr += 1;
                    }
                    if (i < size) {
                        i += readBytesAs(DLT, &self.ptr);
                    }
                }
                // we updated one data record
                self.data_idx += 1;
            }
            // initialize the page
            const diff = self.ptr - storage;
            self.page_idx = diff / page_size;
            self.page_offset = diff % page_size;
            // copy data until offset
            const p = storage + self.page_idx * page_size;
            for (0..self.page_offset) |i| {
                self.page[i] = p[i];
            }
            return &self.data;
        }

        // write to page, change page if necessary
        pub fn writeBytes(self: *Self, bytes: []const u8) void {
            if (self.page_idx == pages) {
                // we are full
                return;
            }
            for (0..bytes.len) |i| {
                self.page[self.page_offset] = bytes[i];
                self.page_offset += 1;
                if (self.page_offset == page_size) {
                    // the page is full, write it
                    write_page(self.page_idx, &self.page);
                    self.page_idx += 1;
                    self.page_offset = 0;
                    if (self.page_idx == pages) {
                        // we are full
                        return;
                    }
                }
                self.ptr += 1;
            }
        }

        fn writeAsBytes(self: *Self, v: anytype) void {
            self.writeBytes(mem.asBytes(v));
        }

        pub fn write(self: *Self, data: []const u8) void {
            if (self.ptr == storage) {
                // first write without a former read,
                // read the chronological data first
                _ = self.read();
            }
            if (self.ptr == storage) {
                // the first write, we have to write the magic bytes first
                self.writeBytes(magic_bytes);
            }

            var begin: DLT = 0;
            var skip: DLT = 0;
            // write the data_size
            self.writeAsBytes(&data_size);
            for (0..data.len) |i_| {
                const i = @as(DLT, @intCast(i_));
                if (data[i] == self.data[i]) {
                    // data are equal
                    if (skip == 0 and i > 0) {
                        // we have to write the bytes which are not equal
                        self.writeAsBytes(&(i - begin));
                        self.writeBytes(data[begin..i]);
                    }
                    skip += 1;
                } else {

                    // data are not equal
                    if (skip > 0 or i == 0) {
                        // we change from a skipped range to unskipped one
                        begin = i;
                        self.writeAsBytes(&skip);
                        skip = 0;
                    }
                }
            }
            if (skip == 0) {
                // we have to write the bytes which are not equal
                self.writeAsBytes(&(@as(DLT, @intCast(data.len)) - begin));
                self.writeBytes(data[begin..data.len]);
            } else {
                //
                self.writeAsBytes(&skip);
            }
            // now write the end, this is the next size entry as zero
            self.writeAsBytes(&(@as(DLT, 0)));
            if (self.page_idx < pages and self.page_offset > 0) {
                write_page(self.page_idx, &self.page);
            }
            if (self.page_idx == pages) {
                // we are full
                // todo: make a new start and write out the data
            }

            self.ptr -= @sizeOf(DLT);
            // todo: go back with the page offset to, what to do if
            // page_idx goes back as well...
            mem.copyForwards(u8, &self.data, data);
        }
    };
}

fn TestStorage(
    comptime page_size: usize,
    comptime pages: usize,
) type {
    const bytes = page_size * pages;
    return struct {
        pub var storage: [bytes]u8 = [_]u8{0} ** (bytes);
        pub fn get_storage() [*]const u8 {
            return &storage;
        }
        pub fn write_page(page_idx: usize, page: []const u8) void {
            assert(page.len == page_size);
            assert(page_idx < pages);
            var i = page_idx * page_size;
            for (page) |b| {
                storage[i] = b;
                i += 1;
            }
        }
    };
}

test {
    const page_size = 16;
    const pages = 2;

    const storage = comptime TestStorage(page_size, pages);

    const data_size = 4;
    const data = "abcd";
    {
        var fj = comptime create(u8, data_size, data_size, page_size, pages, storage.get_storage(), storage.write_page){};
        fj.write(data);
        try testing.expectEqualSlices(
            u8,
            &.{ 'f', 'j', 4, 0, 4, 'a', 'b', 'c', 'd', 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
            storage.get_storage()[0 .. page_size * pages],
        );
        try testing.expectEqualSlices(u8, data, fj.read());
    }
    {
        var fj = comptime create(u8, data_size, data_size, page_size, pages, storage.get_storage(), storage.write_page){};
        try testing.expectEqualSlices(u8, data, fj.read());
    }
}
