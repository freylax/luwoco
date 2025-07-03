const Pos = @This();
line: u16,
column: u8,
pub fn newLine(p: *Pos) void {
    p.line += 1;
    p.column = 0;
}
pub fn onNewLine(p: *Pos) void {
    if (p.column > 0) {
        p.line += 1;
        p.column = 0;
    }
}
pub fn next(p: *Pos, str: []const u8, line_end: u8) void {
    for (str) |c| {
        switch (c) {
            '\n' => {
                p.newLine();
            },
            else => {
                if (p.column == line_end) {
                    p.newLine();
                } else {
                    p.column += 1;
                }
            },
        }
    }
}
// the position of last printable char
pub fn last(p: Pos, str: []const u8, line_end: u8) Pos {
    var q = p;
    if (str.len > 0) {
        var i: u16 = @intCast(str.len - 1);
        while (i > 0 and (str[i] == ' ' or str[i] == '\n')) {
            i -= 1;
        }
        q.skip(i, line_end);
    }
    return q;
}
pub fn skip_(p: Pos, l: u16, line_end: u8) Pos {
    var q = p;
    for (0..l) |_| {
        if (q.column == line_end) {
            q.line += 1;
            q.column = 0;
        } else {
            q.column += 1;
        }
    }
    return q;
}

pub fn skip(p: *Pos, l: u16, line_end: u8) void {
    for (0..l) |_| {
        if (p.column == line_end) {
            p.newLine();
        } else {
            p.column += 1;
        }
    }
}
