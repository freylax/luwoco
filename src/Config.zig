const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;
const microzig = @import("microzig");
const rp2xxx = microzig.hal;
const flash = rp2xxx.flash;

const FlashJournal = @import("FlashJournal.zig");
// const Range = @import("Range.zig");
const Area = @import("area.zig").Area;
const Self = @This();
const my_size: u8 = @sizeOf(Self);

const page_size = flash.PAGE_SIZE; // is 256
const pages = flash.SECTOR_SIZE / flash.PAGE_SIZE; // 4096 / 256 = 16 pages
const flash_target_offset = 0x20_0000 - flash.SECTOR_SIZE; // 2 MB Flash
const flash_target_contents = @as([*]const u8, @ptrFromInt(flash.XIP_BASE + flash_target_offset));
// this has to be adjusted if more entries are populated
const max_size: u8 = 13;

pub var values: Self = Self{};

// size: 1  1
back_light: u8 = 0,
// size: 4  5
allowed_area: Area(i8) = .{ .x = .{ .min = -5, .max = 5 }, .y = .{ .min = -3, .max = 3 } },
// size: 4  9
work_area: Area(i8) = .{ .x = .{ .min = -2, .max = 2 }, .y = .{ .min = -2, .max = 2 } },
// size: 1  10
cook_time_xs: u8 = 0, // six seconds cook_time, 10xs is 1 minute
// size: 1  11
simulator_sampling_time_cs: u8 = 10, // in centi seconds
// size: 1  12
simulator_switching_time_cs: u8 = 10,
// size: 1  13
simulator_driving_time_ds: u8 = 2, // deci seconds

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

pub fn write(self: *Self) void {
    // disable interrupts during write to flash
    const cs = microzig.interrupt.enter_critical_section();
    defer cs.leave();
    journal.write(mem.asBytes(self));
}

pub fn data_differ(self: *Self) bool {
    return !mem.eql(u8, journal.data[0..my_size], mem.asBytes(self));
}
