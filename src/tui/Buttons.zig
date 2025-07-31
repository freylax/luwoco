const Self = @This();

pub const Error = error{ButtonError};

ptr: *anyopaque,
vtable: *const VTable,

pub const VTable = struct {
    // if no u8 was returned, then
    // an error occured
    read: *const fn (*anyopaque) ?u8,
    oneShot: *const fn (*anyopaque, u8) void,
};
pub inline fn read(d: Self) Error!u8 {
    if (d.vtable.read(d.ptr)) |b| {
        return b;
    } else {
        return error.ButtonError;
    }
}
pub inline fn oneShot(d: Self, b: u8) void {
    d.vtable.oneShot(d.ptr, b);
}

pub const Event = enum {
    up,
    down,
    left,
    right,
    none,
};
