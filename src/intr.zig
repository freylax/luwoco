const microzig = @import("microzig");
const hal = microzig.hal;
const chip = microzig.chip;

// I don't actually know if this needs to be callconv C
pub fn gpio_handler() callconv(.C) void {
    // Acknowledge/clear the interrupt. With an edge-triggered interrupt,
    //  when missing the acknowledge, the interrupt triggers repeatedly forever
    // We're "listening" for falling-edge events on pin 18
    // Search for "INTR0 Register" in the rp2040 datasheet
    // You can also read this register to determine which events have triggered
    // Note: This line is deceptive. It acknowledges every outstanding GPIO event on INTR2
    //     because modify is implemented as a read and then a write, and other bits will be 1 if they are active
    chip.peripherals.IO_BANK0.INTR2.modify(.{ .GPIO16_EDGE_LOW = 1 });

    // Turn the on-board light on the Pico on and then off
    hal.gpio.num(25).put(1);
    hal.time.sleep_ms(1000);
    hal.gpio.num(25).put(0);
    hal.time.sleep_ms(200);
}

// Insert our handler into the vector table
// Microzig looks for this "microzig_options" struct and inserts the address
// of our handler function into the vector table when linking the program
pub const microzig_options = microzig.Options{
    .interrupts = .{
        .IO_IRQ_BANK0 = .{ .c = gpio_handler },
    },
};

const pin_config = hal.pins.GlobalConfiguration{
    // on board LED
    .GPIO25 = .{
        .name = "led_1",
        .direction = .out,
    },
    // Button
    .GPIO16 = .{
        .name = "button_1",
        .direction = .in,
        .pull = .up,
    },
};

pub fn main() noreturn {
    // The intention is that you can short this high by pressing a button,
    //  and when releasing the button, the interrupt will fire
    _ = pin_config.apply();

    // Enable the GPIO interrupt for the GPIO bank
    // 13 is IO_IRQ_BANK0. This bit field isn't defined in the svd
    // Search for "NVIC_ISER" and "IO_IRQ_BANK0" in the rp2040 datasheet for more info
    chip.peripherals.PPB.NVIC_ISER.modify(.{
        .SETENA = 1 << 13, // 13 is IO_IRQ_BANK0
    });

    // TODO: "Clear stale events which might cause immediate spurious handler entry"
    // https://github.com/raspberrypi/pico-sdk/blob/6a7db34ff63345a7badec79ebea3aaef1712f374/src/rp2_common/hardware_gpio/gpio.c#L164C8-L164C77

    // Mask the interrupt to only fire on the falling-edge of pin 18
    // Without this, the handler would run for every event on every pin
    // "2.19.3. Interrupts" is of course helpful
    // As with INTR, the 32 pins are split across 4 registers, since each has 4 possible events
    // * PROC0_INTE0 handles GPIO pins 0 to 7
    // * PROC0_INTE1 handles GPIO pins 8 to 15
    // * PROC0_INTE2 handles GPIO pins 16 to 23
    // * PROC0_INTE3 handles GPIO pins 24 to 31
    // Our button is on 18, so we want PROC0_INTE2
    // And we want to trigger on the high (1)->low (0) edge for the demo
    // That's GPIO18_EDGE_LOW
    chip.peripherals.IO_BANK0.PROC0_INTE2.modify(.{ .GPIO16_EDGE_LOW = 1 });

    // Heartbeat so we know it's running
    while (true) {
        hal.gpio.num(25).put(1);
        hal.time.sleep_ms(100);
        hal.gpio.num(25).put(0);
        hal.time.sleep_ms(900);
    }
}
