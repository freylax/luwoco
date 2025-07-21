pub const Tag = enum {
    section,
    value,
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
};

id: u16,
pl: PayLoad,
