const microzig = @import("microzig");
const rp2xxx = microzig.hal;
const adc = rp2xxx.adc;
const time = microzig.drivers.time;

const Self = @This();
const State = enum {
    adc_read,
    paused,
};

enable: *bool,
input: adc.Input,
nr_of_samples: *u8,
pause_time_cs: *u8,

state: State = .paused,
timer_us: u64 = 0,
timer_update_us: u64 = 0,
value: ?u8 = null,
value_cycle: ?u12 = null,
sample_counter: u8 = 0,

pub fn begin(self: *Self) void {
    adc.apply(.{ .temp_sensor_enabled = self.input == .temp_sensor });
    adc.select_input(self.input);
}

const CallSample = enum { soon, later };
pub fn sample(self: *Self, sample_time: time.Absolute) !CallSample {
    if (self.enable.*) {
        switch (self.state) {
            .paused => {
                const sample_time_us = sample_time.to_us();
                self.timer_us -|= sample_time_us -| self.timer_update_us;
                self.timer_update_us = sample_time_us;
                if (self.timer_us == 0) {
                    adc.start(.one_shot);
                    self.value_cycle = null;
                    self.state = .adc_read;
                    return .soon;
                }
                return .later;
            },
            .adc_read => {
                if (adc.is_ready()) {
                    const res = try adc.read_result();
                    if (self.value_cycle) |v| {
                        self.value_cycle = @max(v, res);
                    } else {
                        self.value_cycle = res;
                    }
                    self.sample_counter += 1;
                    if (self.sample_counter == self.nr_of_samples.*) {
                        if (self.value_cycle) |v| {
                            self.value = @intCast(v >> 4);
                        } else {
                            self.value = null;
                        }
                        self.timer_us = @as(u64, self.pause_time_cs.*) *| 10_000;
                        self.timer_update_us = sample_time.to_us();
                        self.sample_counter = 0;
                        self.state = .paused;
                        return .later;
                    } else {
                        adc.start(.one_shot);
                    }
                }
                return .soon;
            },
        }
    } else {
        self.state = .paused;
        self.value = null;
        return .later;
    }
}
