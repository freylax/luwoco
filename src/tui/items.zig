const Event = @import("Event.zig");

pub const ItemTag = enum(u2) {
    popup,
    embed,
    value,
    label,
};

pub const ItemTagLen = @typeInfo(ItemTag).@"enum".fields.len;

pub const Embed = struct {
    id: ?u16 = null,
    str: []const u8,
    items: []const Item,
};

pub const Popup = struct {
    id: ?u16 = null,
    str: []const u8,
    items: []const Item,
};

pub const ValueTag = enum(u1) {
    ro,
    rw,
};

pub const RoValue = struct {
    size: u8,
    ptr: *anyopaque,
    vtable: *const VTable,
    pub const VTable = struct {
        get: *const fn (*anyopaque) []const u8,
    };
    pub inline fn get(v: RoValue) []const u8 {
        return v.vtable.get(v.ptr);
    }
};

pub const RwValue = struct {
    id: ?u16 = null,
    size: u8,
    ptr: *anyopaque,
    vtable: *const VTable,
    pub const VTable = struct {
        get: *const fn (*anyopaque) []const u8,
        inc: *const fn (*anyopaque) ?Event,
        dec: *const fn (*anyopaque) ?Event,
    };
    pub inline fn get(v: RwValue) []const u8 {
        return v.vtable.get(v.ptr);
    }
    pub inline fn inc(v: RwValue) ?Event {
        return v.vtable.inc(v.ptr);
    }
    pub inline fn dec(v: RwValue) ?Event {
        return v.vtable.dec(v.ptr);
    }
};

pub const Value = union(ValueTag) {
    ro: RoValue,
    rw: RwValue,
    pub inline fn size(v: Value) u8 {
        return switch (v) {
            .ro => |ro| ro.size,
            .rw => |rw| rw.size,
        };
    }
    pub inline fn get(v: Value) []const u8 {
        return switch (v) {
            .ro => |ro| ro.get(),
            .rw => |rw| rw.get(),
        };
    }
};

pub const Item = union(ItemTag) {
    popup: Popup,
    embed: Embed,
    value: Value,
    label: []const u8,
};
