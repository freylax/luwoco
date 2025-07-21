const std = @import("std");
const Pos = @import("tui/Pos.zig");
const Display = @import("tui/Display.zig");
const Tree = @import("tui/Tree.zig");

const Item = Tree.Item;
const ItemTag = Tree.ItemTag;
const Value = @import("tui/items.zig").Value;
pub const Event = @import("tui/Event.zig");

const TUI = @This();

ptr: *anyopaque,
vtable: *const VTable,
pub const VTable = struct {
    buttonEvent: *const fn (*anyopaque, Display.Button) ?Event,
    writeValues: *const fn (*anyopaque) void,
    print: *const fn (*anyopaque) ?void,
};

pub inline fn buttonEvent(t: TUI, b: Display.Button) ?Event {
    return t.vtable.buttonEvent(t.ptr, b);
}
pub inline fn writeValues(t: TUI) void {
    t.vtable.writeValues(t.ptr);
}
pub fn print(t: TUI) Display.Error!void {
    if (t.vtable.print(t.ptr)) |_| {} else {
        return error.DisplayError;
    }
}

const RtItemTag = enum(u2) {
    section,
    value,
    label,
};

const RtItem = struct {
    tag: RtItemTag,
    pos: Pos,
    ptr: u16, // specific ptr into tag array
    last: Pos, // pos of last printable char
};

const SectionType = enum(u2) {
    normal,
    one_value,
};

const SectionMode = enum(u2) {
    select_item,
    change_value,
};

const RtSection = struct {
    type: SectionType = .normal,
    mode: SectionMode = .select_item,
    begin: u16, // first item
    end: u16, // item which does not belong to this section
    cursor: u16 = 0, // the current cursor item (down)
    parent: u16 = 0, // parent section (up)
    lines: [2]u16, // displayed lines
    id: ?u16, // event id if available
};

const RtValue = struct {
    item: u16,
    value: Value,
};

pub fn Impl(comptime tree: Tree) type {
    return struct {
        const Self = @This();
        const nrRtSections = tree.nrItems[@intFromEnum(ItemTag.popup)] //
            + tree.nrItems[@intFromEnum(ItemTag.embed)] + 1;
        const nrRtValues = tree.nrItems[@intFromEnum(ItemTag.value)];
        const nrRtLabels = tree.nrItems[@intFromEnum(ItemTag.label)];
        const nrRtItems = nrRtSections + nrRtValues + nrRtLabels;

        display: Display = undefined,
        tree: Tree = tree,
        items: [nrRtItems]RtItem = undefined,
        sections: [nrRtSections]RtSection = undefined,
        values: [nrRtValues]RtValue = undefined,

        curSection: u16 = 0,
        const Idx = struct {
            item: u16,
            section: u16,
            value: u16,
        };

        pub fn init(display: Display) Self {
            return Self{
                .display = display,
            };
        }
        pub fn tui(self: *Self) TUI {
            var pos = Pos{ .column = 0, .line = 0 };
            var idx = Idx{ .item = 1, .section = 1, .value = 0 };
            // the root item
            self.items[0] = .{ .tag = .section, .pos = pos, .ptr = 0, .last = pos };
            self.sections[0] = .{
                .begin = 1,
                .end = @intCast(1 + self.tree.items.len),
                .cursor = 1,
                .parent = 0,
                .lines = .{ 0, 1 },
                .id = null, // no event for root section
            };
            initMenuR(self, self.tree.items, &pos, &idx, 0);
            checkSections(self);

            return .{
                .ptr = self,
                .vtable = &.{
                    .buttonEvent = buttonEventImpl,
                    .writeValues = writeValuesImpl,
                    .print = printImpl,
                },
            };
        }

        fn initMenuR(self: *Self, l: []const Item, pos: *Pos, idx: *Idx, parent: u16) void {
            const item_start = idx.item;
            initMenuHead(self, l, pos, idx, parent);
            initMenuTail(self, l, pos, idx, item_start);
        }

        fn initMenuHead(self: *Self, l: []const Item, pos: *Pos, idx: *Idx, parent: u16) void {
            const item_start = idx.item;
            idx.item += @intCast(l.len);
            for (l, item_start..) |i, j| {
                switch (i) {
                    .popup => |pop| {
                        self.display.write(pos.line, pos.column, pop.str);
                        self.items[j] = .{
                            .tag = .section,
                            .pos = pos.*,
                            .ptr = idx.section,
                            .last = pos.*.last(pop.str, tree.line_end),
                        };
                        self.sections[idx.section] = .{
                            .begin = 0,
                            .end = 0,
                            .parent = parent,
                            .lines = .{ 0, 0 },
                            .id = pop.id,
                        }; // this will be filled in initMenuTail
                        pos.next(pop.str, tree.line_end);
                        idx.section += 1;
                    },
                    .embed => |emb| {
                        self.display.write(pos.line, pos.column, emb.str);
                        self.items[j] = .{
                            .tag = .section,
                            .pos = pos.*,
                            .ptr = idx.section,
                            .last = pos.*.last(emb.str, tree.line_end),
                        };
                        const line = self.items[idx.item].pos.line;
                        const end: u16 = @intCast(idx.item + emb.items.len);
                        self.sections[idx.section] = .{
                            .begin = idx.item,
                            .end = end,
                            .parent = parent,
                            .cursor = idx.item,
                            .lines = if (end > idx.item and line < self.items[end - 1].last.line)
                                .{ line, line + 1 }
                            else
                                .{ self.items[j].pos.line, line },
                            .id = emb.id,
                        };
                        pos.next(emb.str, tree.line_end);
                        const this_section = idx.section;
                        idx.section += 1;
                        initMenuR(self, emb.items, pos, idx, this_section);
                    },
                    .label => |lbl| {
                        self.display.write(pos.line, pos.column, lbl);
                        self.items[j] = .{
                            .tag = .label,
                            .pos = pos.*,
                            .ptr = 0,
                            .last = pos.*.last(lbl, tree.line_end),
                        };
                        pos.next(lbl, tree.line_end);
                    },
                    .value => |val| {
                        const s = "xxxxxxxxxxxxxx";
                        self.display.write(pos.line, pos.column, s[0..val.size()]);
                        self.items[j] = .{
                            .tag = .value,
                            .pos = pos.*,
                            .ptr = idx.value,
                            .last = pos.*.skip_(val.size() - 1, tree.line_end),
                        };
                        pos.skip(val.size(), tree.line_end);
                        self.values[idx.value] = .{
                            .item = @intCast(j),
                            .value = val,
                        };
                        idx.value += 1;
                    },
                }
            }
        }

        fn initMenuTail(self: *Self, l: []const Item, pos: *Pos, idx: *Idx, item_start: u16) void {
            for (l, item_start..) |i, j| {
                switch (i) {
                    .popup => |pop| {
                        pos.onNewLine();
                        const idx_ = idx.*; // get a copy
                        initMenuR(self, pop.items, pos, idx, self.items[j].ptr); //@intCast(j));
                        if (pop.items.len > 0) {
                            const sec: *RtSection = &self.sections[self.items[j].ptr];
                            sec.begin = idx_.item;
                            sec.end = @intCast(idx_.item + pop.items.len);
                            sec.cursor = idx_.item;
                            const line = self.items[sec.begin].pos.line;
                            // test if we have only one line in the section
                            if (line == self.items[sec.end - 1].last.line) {
                                // then we show the parent and the section line
                                sec.lines = .{ self.items[j].pos.line, line };
                            } else {
                                // otherwise the two lines will display the first two lines of the section
                                sec.lines = .{ line, line + 1 };
                            }
                        }
                    },
                    else => {},
                }
            }
        }
        // setup the initial cursor positions
        // and modi for values
        fn checkSections(self: *Self) void {
            for (&self.sections) |*s| {
                // count number of values in this section
                var i: u16 = s.begin;
                var first_selectable: ?u16 = null;
                var c_val: u16 = 0;
                var c_sec: u16 = 0;
                while (i != s.end) {
                    const item = self.items[i];
                    switch (item.tag) {
                        .value => {
                            if (switch (self.values[item.ptr].value) {
                                .ro => false,
                                .rw => true,
                            }) {
                                c_val += 1;
                            }
                        },
                        .section => {
                            c_sec += 1;
                        },
                        else => {},
                    }
                    if (c_sec + c_val == 1) {
                        first_selectable = i;
                    }
                    i += 1;
                }
                if (first_selectable) |first| {
                    s.cursor = first;
                    if (c_val == 1 and c_sec == 0) {
                        s.type = .one_value;
                        s.mode = .change_value;
                    }
                }
            }
        }

        fn hasCursor(self: *Self, item_idx: u16) bool {
            const item: RtItem = self.items[item_idx];
            return switch (item.tag) {
                .section => true,
                .value => switch (self.values[item.ptr].value) {
                    .ro => false,
                    .rw => true,
                },
                .label => false,
            };
        }

        fn advanceCursor(self: *Self, dir: Display.Button) ?Event {
            const sec: *RtSection = &self.sections[self.curSection];
            const lines = &sec.lines;
            var event: ?Event = null;
            // test if there are members in this section
            if (sec.begin == sec.end) {
                return event;
            }
            switch (sec.mode) {
                .select_item => switch (dir) {
                    .none => {},
                    .left => {
                        // first we check if we only have to scroll backwards,
                        // this is the case if the cursor item pos is not visible right now
                        if (lines[0] > self.items[sec.cursor].pos.line) {
                            // just decrease lines
                            lines[1] = lines[0];
                            lines[0] -= 1;
                        } else {
                            // if only one item, do not move cursor
                            if (sec.begin + 1 == sec.end) {
                                return event;
                            }
                            const start = sec.cursor; // since we cycle around we need a stop
                            while (sec.cursor >= sec.begin) {
                                var line_changed = false;
                                if (sec.cursor == sec.begin) {
                                    sec.cursor = sec.end - 1;
                                    const li = self.items[sec.cursor].last.line;
                                    if (li != lines[0] and li != lines[1]) {
                                        lines[0] = li - 1;
                                        lines[1] = li;
                                        line_changed = true;
                                    }
                                } else {
                                    sec.cursor -= 1;
                                    if (self.items[sec.cursor].pos.line < lines[0]) {
                                        // decrease lines
                                        lines[1] = lines[0];
                                        lines[0] -= 1;
                                        line_changed = true;
                                    }
                                }
                                if (start == sec.cursor or line_changed or self.hasCursor(sec.cursor)) break;
                            }
                        }
                    },
                    .right => {
                        // check if we have to scroll forward
                        if (lines[1] < self.items[sec.cursor].last.line) {
                            // log.info("right,A", .{});
                            // increase lines
                            lines[0] = lines[1];
                            lines[1] += 1;
                        } else {
                            // log.info("right,B", .{});
                            // if only one item, do not move cursor
                            if (sec.begin + 1 == sec.end) {
                                return event;
                            }
                            const start = sec.cursor; // since we cycle around we need a stop
                            while (sec.cursor < sec.end) {
                                var line_changed = false;
                                if (sec.cursor + 1 == sec.end) {
                                    // log.info("right,C", .{});
                                    sec.cursor = sec.begin;
                                    const li = self.items[sec.cursor].pos.line;
                                    if (li != lines[0] and li != lines[1]) {
                                        // log.info("right,D", .{});
                                        lines[0] = li;
                                        lines[1] = li + 1;
                                        line_changed = true;
                                    }
                                } else {
                                    // log.info("right,E", .{});
                                    sec.cursor += 1;
                                    if (self.items[sec.cursor].last.line > lines[1]) {
                                        // log.info("right,F", .{});
                                        // increase lines
                                        lines[0] = lines[1];
                                        lines[1] += 1;
                                        line_changed = true;
                                    }
                                }
                                if (start == sec.cursor or line_changed or self.hasCursor(sec.cursor)) break;
                            }
                        }
                    },
                    .up => {
                        if (self.curSection > 0) {
                            if (sec.id) |id| {
                                event = .{ .id = id, .pl = .{ .section = .leave } };
                            }
                            self.curSection = sec.parent;
                        }
                    },
                    .down => {
                        switch (self.items[sec.cursor].tag) {
                            .section => {
                                self.curSection = self.items[sec.cursor].ptr;
                                const sec_: *RtSection = &self.sections[self.curSection];
                                if (sec_.id) |id| {
                                    event = .{ .id = id, .pl = .{ .section = .enter } };
                                }
                            },
                            .value => {
                                // should be on a selectable one
                                sec.mode = .change_value;
                            },
                            else => {},
                        }
                    },
                },
                .change_value => {
                    switch (self.values[self.items[sec.cursor].ptr].value) {
                        .rw => |rw| {
                            switch (dir) {
                                .right => {
                                    event = rw.inc();
                                },
                                .left => {
                                    event = rw.dec();
                                },
                                .down => {},
                                .none => {},
                                .up => {
                                    switch (sec.type) {
                                        .one_value => {
                                            if (sec.id) |id| {
                                                event = .{ .id = id, .pl = .{ .section = .leave } };
                                            }
                                            self.curSection = sec.parent;
                                        },
                                        .normal => {
                                            sec.mode = .select_item;
                                        },
                                    }
                                },
                            }
                        },
                        else => {},
                    }
                },
            }
            return event;
        }

        fn buttonEventImpl(ctx: *anyopaque, button: Display.Button) ?Event {
            const self: *Self = @ptrCast(@alignCast(ctx));

            const ev = advanceCursor(self, button);
            const sec: *RtSection = &self.sections[self.curSection];
            const cItem = self.items[sec.cursor];
            // log.info("cursor item:{d} is at line:{d},column:{d}", .{ sec.cursor, cItem.pos.line, cItem.pos.column });
            if (self.hasCursor(sec.cursor)) {
                self.display.cursor(
                    cItem.pos.line,
                    cItem.pos.column,
                    cItem.last.line,
                    cItem.last.column,
                    switch (sec.mode) {
                        .select_item => .select,
                        .change_value => .change,
                    },
                );
            } else {
                // log.info("set cursor off", .{});
                self.display.cursorOff();
            }
            return ev;
        }

        fn writeValuesImpl(ctx: *anyopaque) void {
            const self: *Self = @ptrCast(@alignCast(ctx));
            const sec: *RtSection = &self.sections[self.curSection];
            const lines = &sec.lines;
            // iterate over the values and write those which are
            // in the current display area
            for (self.values) |rval| {
                const item: *RtItem = &self.items[rval.item];
                if ((item.pos.line <= lines[0] and lines[0] <= item.last.line) or (item.pos.line <= lines[1] and lines[1] <= item.last.line))
                    self.display.write(item.pos.line, item.pos.column, rval.value.get());
            }
        }
        fn printImpl(ctx: *anyopaque) ?void {
            const self: *Self = @ptrCast(@alignCast(ctx));
            const sec: *RtSection = &self.sections[self.curSection];
            const lines = &sec.lines;
            self.display.print(lines) catch return null;
        }
    };
}
