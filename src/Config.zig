const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;
const microzig = @import("microzig");
const rp2xxx = microzig.hal;
const flash = rp2xxx.flash;

const FlashJournal = @import("FlashJournal.zig");

const Self = @This();
const my_size: u8 = @sizeOf(Self);

const page_size = flash.PAGE_SIZE; // is 256
const pages = flash.SECTOR_SIZE / flash.PAGE_SIZE; // 4096 / 256 = 16 pages
const flash_target_offset = 0x20_0000 - flash.SECTOR_SIZE; // 2 MB Flash
const flash_target_contents = @as([*]const u8, @ptrFromInt(flash.XIP_BASE + flash_target_offset));
// this has to be adjusted if more entries are populated
const max_size: u8 = 5;

pub var values: Self = Self{};

back_light: u8 = 0,
min_x: i8 = -5,
max_x: i8 = 5,
min_y: i8 = -3,
max_y: i8 = 3,

fn write_page(page_idx: usize, page: []const u8) void {
    comptime assert(max_size >= my_size);
    comptime assert(flash_target_offset % page_size == 0);
    const addr = flash_target_offset + page_idx * page_size;
    // std.log.info("write_page({d}): at {x}, [{d}..{d}]:{x}", .{ page_idx, addr, 0, page.len, page[0..50] });
    flash.range_program(addr, page);
}

fn erase_sector() void {
    // std.log.info("erase_sector", .{});
    flash.range_erase(flash_target_offset, 1);
}

var journal = FlashJournal.create(
    u8,
    max_size,
    page_size,
    pages,
    flash_target_contents,
    write_page,
    erase_sector,
){};

pub fn read(self: *Self) void {
    mem.copyForwards(u8, mem.asBytes(self), journal.read());
}
pub fn read_() void {
    read(@ptrCast(&values));
}

pub fn write(self: *Self) void {
    const cs = microzig.interrupt.enter_critical_section();
    defer cs.leave();
    journal.write(mem.asBytes(self));
}

pub fn data_differ(self: *Self) bool {
    return !mem.eql(u8, journal.data[0..my_size], mem.asBytes(self));
}
