const Pos = @import("Pos.zig");
const items_ = @import("items.zig");

pub const Item = items_.Item;
pub const ItemTag = items_.ItemTag;
pub const ItemTagLen = items_.ItemTagLen;

const Tree = @This();

line_end: u8,
items: []const Item,
nrItems: [ItemTagLen]u16,
totalNrItems: u16,
bufferLines: u16,

pub fn create(items: []const Item, line_end: u8) Tree {
    const nrItems = calcTreeSize: {
        var counter = [_]u16{0} ** ItemTagLen;
        treeSize(items, &counter);
        break :calcTreeSize counter;
    };

    return .{
        .line_end = line_end,
        .items = items,
        .nrItems = nrItems,
        .totalNrItems = sumUp: {
            var i = 0;
            for (0..ItemTagLen) |j| {
                i += nrItems[j];
            }
            break :sumUp i;
        },
        .bufferLines = calcLines: {
            var pos = Pos{ .line = 0, .column = 0 };
            advancePos(items, &pos, line_end);
            if (pos.column > 0) {
                pos.line += 1;
            }
            break :calcLines pos.line;
        },
    };
}

fn treeSize(l: []const Item, count: *[ItemTagLen]u16) void {
    for (l) |i| {
        switch (i) {
            .popup => |p| {
                treeSize(p.items, count);
            },
            .embed => |e| {
                treeSize(e.items, count);
            },
            else => {},
        }
        const tag = @as(ItemTag, i);
        count[@intFromEnum(tag)] += 1;
    }
}

fn advancePosHead(l: []const Item, pos: *Pos, line_end: u8) void {
    for (l) |i| {
        switch (i) {
            .popup => |pop| {
                pos.next(pop.str, line_end);
            },
            .embed => |emb| {
                pos.next(emb.str);
                advancePos(emb.items, pos);
            },
            .label => |lbl| {
                pos.next(lbl, line_end);
            },
            .value => |val| {
                pos.skip(val.size(), line_end);
            },
        }
    }
}
fn advancePosTail(l: []const Item, pos: *Pos, line_end: u8) void {
    for (l) |i| {
        switch (i) {
            .popup => |pop| {
                pos.onNewLine(); // there the popups can go
                advancePos(pop.items, pos, line_end);
            },
            else => {},
        }
    }
}
fn advancePos(l: []const Item, pos: *Pos, line_end: u8) void {
    advancePosHead(l, pos, line_end);
    advancePosTail(l, pos, line_end);
}
