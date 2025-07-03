const Self = @This();

pub const CursorType = enum {
    select,
    change,
};

pub const Button = enum {
    up,
    down,
    left,
    right,
    none,
};

pub const Error = error{DisplayError};

lines: u8,
columns: u8,

ptr: *anyopaque,
vtable: *const VTable,

pub const VTable = struct {
    write: *const fn (*anyopaque, line: u16, column: u8, str: []const u8) void,
    cursorOff: *const fn (*anyopaque) void,
    cursor: *const fn (*anyopaque, bLine: u16, bCol: u8, eLine: u16, eCol: u8, CursorType) void,
    // if return false, then an Error did happen
    print: *const fn (*anyopaque, print_lines: []const u16) ?void,
    // if no Button was returned, then
    readButtons: *const fn (*anyopaque) ?Button,
};
pub inline fn write(d: Self, line: u16, column: u8, str: []const u8) void {
    d.vtable.write(d.ptr, line, column, str);
}
pub inline fn cursorOff(d: Self) void {
    d.vtable.cursorOff(d.ptr);
}
pub inline fn cursor(d: Self, bLine: u16, bCol: u8, eLine: u16, eCol: u8, t: CursorType) void {
    d.vtable.cursor(d.ptr, bLine, bCol, eLine, eCol, t);
}
pub inline fn print(d: Self, print_lines: []const u16) Error!void {
    if (d.vtable.print(d.ptr, print_lines)) |_| {} else {
        return error.DisplayError;
    }
}
pub inline fn readButtons(d: Self) Error!Button {
    if (d.vtable.readButtons(d.ptr)) |b| {
        return b;
    } else {
        return error.DisplayError;
    }
}
