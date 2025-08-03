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

pub const ValueTag = enum(u2) {
    ro,
    rw,
    button,
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

pub const ButtonValue = struct {
    pub const Behavior = enum {
        one_click,
        radio_button,
        push_button,
    };
    id: ?u16 = null,
    size: u8,
    behavior: Behavior,
    ptr: *anyopaque,
    vtable: *const VTable,
    pub const VTable = struct {
        get: *const fn (*anyopaque) []const u8,
        set: *const fn (*anyopaque) ?Event,
        reset: *const fn (*anyopaque) ?Event,
        enabled: *const fn (*anyopaque) bool,
    };
    pub inline fn get(v: ButtonValue) []const u8 {
        return v.vtable.get(v.ptr);
    }
    pub inline fn set(v: ButtonValue) ?Event {
        return v.vtable.set(v.ptr);
    }
    pub inline fn reset(v: ButtonValue) ?Event {
        return v.vtable.reset(v.ptr);
    }
    pub inline fn enabled(v: ButtonValue) bool {
        return v.vtable.enabled(v.ptr);
    }
};

pub const Value = union(ValueTag) {
    ro: RoValue,
    rw: RwValue,
    button: ButtonValue,
    pub inline fn size(v: Value) u8 {
        return switch (v) {
            .ro => |ro| ro.size,
            .rw => |rw| rw.size,
            .button => |button| button.size,
        };
    }
    pub inline fn get(v: Value) []const u8 {
        return switch (v) {
            .ro => |ro| ro.get(),
            .rw => |rw| rw.get(),
            .button => |button| button.get(),
        };
    }
};

pub const Item = union(ItemTag) {
    popup: Popup,
    embed: Embed,
    value: Value,
    label: []const u8,
};
