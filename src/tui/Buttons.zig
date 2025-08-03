const Self = @This();

pub const Error = error{ButtonError};

ptr: *anyopaque,
vtable: *const VTable,

pub const VTable = struct {
    // if no u8 was returned, then
    // an error occured
    read: *const fn (*anyopaque) ?u8,
};
pub inline fn read(d: Self) Error!u8 {
    if (d.vtable.read(d.ptr)) |b| {
        return b;
    } else {
        return error.ButtonError;
    }
}
