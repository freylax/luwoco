pub fn Range(comptime T: type) type {
    return struct {
        min: T,
        max: T,
    };
}
