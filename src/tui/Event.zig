pub const Tag = enum {
    section,
    value,
    button,
};

pub const Section = enum {
    enter,
    leave,
};

// pub const Value = enum {
//     changed,
// };

pub const PayLoad = union(Tag) {
    section: Section,
    value: u8,
    button: bool,
};

id: u16,
pl: PayLoad,
