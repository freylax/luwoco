const std = @import("std");
const mem = std.mem;
const log = std.log;
const assert = std.debug.assert;
const microzig = @import("microzig");
const rp2xxx = microzig.hal;
const flash = rp2xxx.flash;

const FlashJournal = @import("FlashJournal.zig");

const Self = @This();
// this has to be adjusted if more entries are populated
const max_size: u8 = 1;
const my_size: u8 = @sizeOf(Self);

const page_size = flash.PAGE_SIZE; // is 256
const pages = 2; // 2 pages
const flash_target_offset = 0x20_0000 - pages * page_size; // 2 MB Flash
const flash_target_contents = @as([*]const u8, @ptrFromInt(flash.XIP_BASE + flash_target_offset));

back_ground_light: u8 = 0,
// min_x: i8 = -5,
// max_x: i8 = 5,
// min_y: i8 = -3,
// max_y: i8 = 3,

fn write_page(page_idx: usize, page: []const u8) void {
    comptime assert(max_size >= my_size);
    comptime assert(flash_target_offset % page_size == 0);
    const addr = flash_target_offset + page_idx * page_size;
    log.info("write_page: at {x}, [{d}..{d}]", .{ addr, 0, page.len });
    flash.range_program(addr, page);
}

var journal = FlashJournal.create(
    u8,
    max_size,
    page_size,
    pages,
    flash_target_contents,
    write_page,
){};

pub fn read(self: *Self) void {
    mem.copyForwards(u8, mem.asBytes(self), journal.read());
}

pub fn write(self: *Self) void {
    journal.write(mem.asBytes(self));
}

pub fn data_differ(self: *Self) bool {
    return !mem.eql(u8, journal.data[0..my_size], mem.asBytes(self));
}
