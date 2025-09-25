# luwoco
Lumber Wood Cook, automatic position of microwave, 
Raspberry Pi Pico rp2040 programmed with microzig

## Controler for rasterize spread out lumber with a micro wave
- The machine is like a huge xy plotter (2x5m), instead of the pen we have the
  micro wave which has to be positioned by aequidistant positions. 
  On each position the microwave has to linger for a certain time,
  thus the wood can be heated. After this the next position will be 
  approached.
- The drives are 24V DC motors. The positions will be detected by activatet switches.
- The controler has a LCD (2x16 characters) and four buttons for entering the paramaters
  and see the working state.  

## Controler Hardware

- Raspberry Pi Pico
- [Olimex LCD Shield 16x2](https://www.olimex.com/Products/Duino/Shields/SHIELD-LCD16x2/open-source-hardware),
  I2C connected 
- H Bridge and Relais for driving the motors and control the microwave

## Software

- written in the enjoyable [Zig language](https://ziglang.org), version 0.15.1 and 
  the [MicroZig](https://github.com/ZigEmbeddedGroup/microzig) framework
- a generic Text User Interface (TUI) was implemented to allow a declarative
  arrangement of a hierarchical user interface
- storing parameters to flash logs the changes accumulative   
  thus the changing of bits will be minimalized (wear leveling)

### TUI

- the goal was to have an easy way to describe the user interface
- a compile time static tree declares the user interface, no dynamic allocations
- Menues, Text, Buttons, Number selections
- sources: src/TUI.zig, src/tui/*.zig
- declarative application: src/main.zig

### Flash Journal 

- Use a byte array as storage type, the size may vary over the development period 
  of the application.
- For storing configuration data use a struct which will be serialized into the byte array.
- source: src/FlashJournal.zig
- application: src/Config.zig
