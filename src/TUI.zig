const std = @import("std");
const Pos = @import("tui/Pos.zig");
const Display = @import("tui/Display.zig");
const Tree = @import("tui/Tree.zig");

const Item = Tree.Item;
const ItemTag = Tree.ItemTag;
const AdditionalCounters = Tree.AdditionalCounters;
const Value = @import("tui/items.zig").Value;
pub const Event = @import("tui/Event.zig");

const TUI = @This();

ptr: *anyopaque,
vtable: *const VTable,
pub const VTable = struct {
    buttonEvent: *const fn (*anyopaque, u8) []const Event,
    writeValues: *const fn (*anyopaque) void,
    print: *const fn (*anyopaque) ?void,
};

pub inline fn buttonEvent(t: TUI, b: u8) []const Event {
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

const RtSection = struct {
    const Mode = enum(u2) {
        select_item,
        change_value,
    };

    const Tag = enum {
        standard,
        one_value,
        direct,
    };

    const Type = union(Tag) {
        standard: Mode,
        one_value: void,
        direct: []const struct { u8, u16 }, // mapping of button mask to values
    };

    type: Type = .{ .standard = .select_item },
    // mode: SectionMode = .select_item,
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

pub const ButtonSemantics = enum {
    escape,
    left,
    right,
    activate,
};

pub const ButtonSemanticsLen = @typeInfo(ButtonSemantics).@"enum".fields.len;

pub fn Impl(comptime tree: Tree, button_masks_: []const u8) type {
    return struct {
        const Self = @This();
        const nrRtSections = tree.nrItems[@intFromEnum(ItemTag.popup)] //
            + tree.nrItems[@intFromEnum(ItemTag.embed)] + 1;
        const nrRtValues = tree.nrItems[@intFromEnum(ItemTag.value)];
        const nrRtLabels = tree.nrItems[@intFromEnum(ItemTag.label)];
        const nrRtItems = nrRtSections + nrRtValues + nrRtLabels;
        const nrDirectButtons = tree.nrItems[@intFromEnum(AdditionalCounters.direct_buttons)];
        const button_masks = button_masks_;

        last_buttons: u8 = 0,
        display: Display = undefined,
        tree: Tree = tree,
        items: [nrRtItems]RtItem = undefined,
        sections: [nrRtSections]RtSection = undefined,
        values: [nrRtValues]RtValue = undefined,
        // +1 because indexing not allowed for empty arrays
        direct_buttons: [nrDirectButtons + 1]struct { u8, u16 } = undefined,
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
            var idx = Idx{
                .item = 1,
                .section = 1,
                .value = 0,
            };
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
            var db_i: u16 = 0;
            for (&self.sections) |*s| {
                // count number of values in this section
                var i: u16 = s.begin;
                var first_selectable: ?u16 = null;
                var c_val: u16 = 0;
                var c_sec: u16 = 0;
                const db_b = db_i;
                while (i != s.end) {
                    const item = self.items[i];
                    switch (item.tag) {
                        .value => {
                            const val = self.values[item.ptr].value;
                            switch (val) {
                                .rw, .button => {
                                    c_val += 1;
                                },
                                else => {},
                            }
                            for (val.direct_buttons()) |db| {
                                self.direct_buttons[db_i] = .{ db, item.ptr };
                                db_i += 1;
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
                if (db_i > db_b) {
                    // we have direct button mapping for this section
                    s.type = .{ .direct = self.direct_buttons[db_b..db_i] };
                } else if (first_selectable) |first| {
                    s.cursor = first;
                    if (c_val == 1 and c_sec == 0) {
                        s.type = .one_value;
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
                    .button => |button| if (button.direct_buttons.len > 0) false else true,
                },
                .label => false,
            };
        }

        inline fn buttonMask(b: ButtonSemantics) u8 {
            return button_masks[@intFromEnum(b)];
        }

        inline fn test2m(m: u8, low: u8, high: u8) bool {
            return m != 0 and m & ~low == m and m & high == m;
        }

        inline fn test2(b: ButtonSemantics, low: u8, high: u8) bool {
            return test2m(buttonMask(b), low, high);
        }

        inline fn test1(b: ButtonSemantics, high: u8) bool {
            const m = buttonMask(b);
            return m != 0 and m & high == m;
        }

        inline fn clear(b: ButtonSemantics, v: *u8) void {
            const m = buttonMask(b);
            v.* &= ~m;
        }

        const Events = struct {
            a: [8]Event = undefined,
            i: u8 = 0,
            fn slice(self: Events) []const Event {
                return self.a[0..self.i];
            }
        };

        inline fn push(l: *Events, e: Event) void {
            l.a[l.i] = e;
            l.i += 1;
        }

        inline fn push_o(l: *Events, e: ?Event) void {
            if (e) |ev| {
                push(l, ev);
            }
        }

        fn advanceCursor(self: *Self, but_: u8) []const Event {
            var but = but_; // we tweek this to adjust last_button in cases
            // where we enter and leave sections to inactivate the button release
            const sec: *RtSection = &self.sections[self.curSection];
            const lines = &sec.lines;
            var events = Events{}; // we can have maximal 8 buttons..
            const ev = &events;
            // test if there are members in this section
            if (sec.begin == sec.end) {
                return ev.slice();
            }
            const lbut = self.last_buttons;
            sec_sw: switch (sec.type) {
                .standard => |*mode| {
                    switch (mode.*) {
                        .select_item => {
                            if (test2(.left, lbut, but)) {
                                // first we check if we only have to scroll backwards,
                                // this is the case if the cursor item pos is not visible right now
                                if (lines[0] > self.items[sec.cursor].pos.line) {
                                    // just decrease lines
                                    lines[1] = lines[0];
                                    lines[0] -= 1;
                                } else {
                                    // if only one item, do not move cursor
                                    if (sec.begin + 1 == sec.end) {
                                        break :sec_sw;
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
                            }
                            if (test2(.right, lbut, but)) {
                                // check if we have to scroll forward
                                if (lines[1] < self.items[sec.cursor].last.line) {
                                    // increase lines
                                    lines[0] = lines[1];
                                    lines[1] += 1;
                                } else {
                                    // if only one item, do not move cursor
                                    if (sec.begin + 1 == sec.end) {
                                        break :sec_sw;
                                    }
                                    const start = sec.cursor; // since we cycle around we need a stop
                                    while (sec.cursor < sec.end) {
                                        var line_changed = false;
                                        if (sec.cursor + 1 == sec.end) {
                                            sec.cursor = sec.begin;
                                            const li = self.items[sec.cursor].pos.line;
                                            if (li != lines[0] and li != lines[1]) {
                                                lines[0] = li;
                                                lines[1] = li + 1;
                                                line_changed = true;
                                            }
                                        } else {
                                            sec.cursor += 1;
                                            if (self.items[sec.cursor].last.line > lines[1]) {
                                                // increase lines
                                                lines[0] = lines[1];
                                                lines[1] += 1;
                                                line_changed = true;
                                            }
                                        }
                                        if (start == sec.cursor or line_changed or self.hasCursor(sec.cursor)) break;
                                    }
                                }
                            }
                            if (test2(.escape, lbut, but)) {
                                if (self.curSection > 0) {
                                    if (sec.id) |id| {
                                        push(ev, .{ .id = id, .pl = .{ .section = .leave } });
                                    }
                                    self.curSection = sec.parent;
                                    clear(.escape, &but);
                                    break :sec_sw;
                                }
                            }
                            const activate_pressed = test2(.activate, lbut, but);
                            const activate_released = test2(.activate, but, lbut);
                            if (activate_pressed or activate_released) {
                                switch (self.items[sec.cursor].tag) {
                                    .section => {
                                        if (activate_pressed) {
                                            self.curSection = self.items[sec.cursor].ptr;
                                            const sec_: *RtSection = &self.sections[self.curSection];
                                            if (sec_.id) |id| {
                                                push(ev, .{ .id = id, .pl = .{ .section = .enter } });
                                            }
                                            clear(.activate, &but);
                                            break :sec_sw;
                                        }
                                    },
                                    .value => {
                                        switch (self.values[self.items[sec.cursor].ptr].value) {
                                            .rw => {
                                                // should be on a selectable one
                                                if (activate_pressed) {
                                                    mode.* = .change_value;
                                                    clear(.activate, &but);
                                                    break :sec_sw;
                                                }
                                            },
                                            .button => |button| {
                                                switch (button.behavior) {
                                                    .push_button, .one_click => {
                                                        if (activate_pressed) {
                                                            push_o(ev, button.set());
                                                        } else if (activate_released) {
                                                            push_o(ev, button.reset());
                                                        }
                                                    },
                                                    else => {},
                                                }
                                            },
                                            else => {},
                                        }
                                    },
                                    else => {},
                                }
                            }
                        },
                        .change_value => {
                            switch (self.values[self.items[sec.cursor].ptr].value) {
                                .rw => |rw| {
                                    if (test2(.right, lbut, but)) {
                                        push_o(ev, rw.inc());
                                    }
                                    if (test2(.left, lbut, but)) {
                                        push_o(ev, rw.dec());
                                    }
                                    if (test1(.escape, but)) {
                                        mode.* = .select_item;
                                        clear(.escape, &but);
                                        break :sec_sw;
                                    }
                                },
                                else => {},
                            }
                        },
                    }
                },
                .one_value => {
                    switch (self.values[self.items[sec.cursor].ptr].value) {
                        .rw => |rw| {
                            if (test2(.right, lbut, but)) {
                                push_o(ev, rw.inc());
                            }
                            if (test2(.left, lbut, but)) {
                                push_o(ev, rw.dec());
                            }
                            if (test2(.escape, lbut, but)) {
                                if (sec.id) |id| {
                                    push(ev, .{ .id = id, .pl = .{ .section = .leave } });
                                }
                                self.curSection = sec.parent;
                                clear(.escape, &but);
                                break :sec_sw;
                            }
                        },
                        else => {},
                    }
                },
                .direct => |map| {
                    var esc_enabled = true;
                    const esc_m = buttonMask(.escape);
                    for (map) |map_i| {
                        const m, const v = map_i;
                        const pressed = test2m(m, lbut, but);
                        const released = test2m(m, but, lbut);
                        if (pressed or released) {
                            switch (self.values[v].value) {
                                .button => |button| {
                                    if (button.enabled()) {
                                        switch (button.behavior) {
                                            .push_button, .one_click => {
                                                if (pressed) {
                                                    push_o(ev, button.set());
                                                } else if (released) {
                                                    push_o(ev, button.reset());
                                                }
                                            },
                                            else => {},
                                        }
                                        if (m == esc_m) {
                                            esc_enabled = false;
                                        }
                                    } else {
                                        switch (button.behavior) {
                                            .one_click => {
                                                if (released) {
                                                    push_o(ev, button.reset());
                                                }
                                            },
                                            else => {},
                                        }
                                    }
                                },
                                else => {},
                            }
                        }
                    }
                    if (esc_enabled and test2(.escape, lbut, but)) {
                        if (sec.id) |id| {
                            push(ev, .{ .id = id, .pl = .{ .section = .leave } });
                        }
                        self.curSection = sec.parent;
                        clear(.escape, &but);
                        break :sec_sw;
                    }
                },
            }
            self.last_buttons = but;
            return ev.slice();
        }

        fn buttonEventImpl(ctx: *anyopaque, buttons: u8) []const Event {
            const self: *Self = @ptrCast(@alignCast(ctx));

            const ev = advanceCursor(self, buttons);
            const sec: *RtSection = &self.sections[self.curSection];
            const cItem = self.items[sec.cursor];
            // log.info("cursor item:{d} is at line:{d},column:{d}", .{ sec.cursor, cItem.pos.line, cItem.pos.column });
            if (self.hasCursor(sec.cursor)) {
                self.display.cursor(
                    cItem.pos.line,
                    cItem.pos.column,
                    cItem.last.line,
                    cItem.last.column,
                    switch (sec.type) {
                        .standard => |mode| switch (mode) {
                            .select_item => .select,
                            .change_value => .change,
                        },
                        else => .change,
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
