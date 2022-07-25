const arduino = @import("arduino");
const std = @import("std");

// Necessary, and has the side effect of pulling in the needed _start method
pub const panic = arduino.start.panicLogUart;

fn hexChar(x: u4) u8 {
    return switch (x) {
        0...9 => @as(u8, '0') + x,
        else => 'a',
    };
}

fn toHex(x: u16, buffer: []u8) []const u8 {
    buffer[3] = hexChar(@intCast(u4, (x >> 0) & 0x000F));
    buffer[2] = hexChar(@intCast(u4, (x >> 4) & 0x000F));
    buffer[1] = hexChar(@intCast(u4, (x >> 8) & 0x000F));
    buffer[0] = hexChar(@intCast(u4, (x >> 12) & 0x000F));
    return buffer[0..4];
}

// export fn __udivmodhi4(number: c_ushort, denomenator: c_ushort, modwanted: c_int) c_ushort
// {
//     var num: c_ushort = number;
//     var den: c_ushort = denomenator;
// 
//     var bit: c_ushort = 1;
//     var res: c_ushort = 0;
// 
//     while (den < num and bit != 0 and den & (1 << 15) != 0) {
//         den <<= 1;
//         bit <<= 1;
//     }
//     while (bit != 0) {
//         if (num >= den) {
//             num -= den;
//             res |= bit;
//         }
//         bit >>=1;
//         den >>=1;
//     }
//     if (modwanted != 0) {
//         return num;
//     }
//     return res;
// }

fn writeU16(value: u16) void {
    arduino.uart.writeCh(@intCast(u8, (value >> 0) & 0x00FF));
    arduino.uart.writeCh(@intCast(u8, (value >> 8) & 0x00FF));
}

fn sendMidiContinousControllPacket(midi_port: u4, channel: u7, value: u7) void {
    arduino.uart.write(&.{
        0xB0 | @intCast(u8, midi_port), // ContinousControll
        channel,
        value, 
        0
    });
}

const button_pins: [4]comptime_int = .{ 5, 4, 3, 2 };

fn setupButtons() void {
    inline for (button_pins) |pin| {
        arduino.gpio.setMode(pin, .input_pullup);
    }
}

fn buttonIsPressed(comptime buttonId: u2) bool {
    const pin = button_pins[buttonId];
    return arduino.gpio.getPin(pin) == .high;
}

pub fn main() void {
    arduino.uart.init(arduino.cpu.CPU_FREQ, 115200);
    setupButtons();

    const running_average_size = 256;
    var running_average = std.mem.zeroes([running_average_size]u8);
    var index: u16 = 0;
    var last_average: u16 = 0;
    var midi_port: u4 = 0;
    var channel: u7 = 0x07; // Volume channel
    while (true) {
        // if (buttonIsPressed(0)) {
        //     midi_port +|= 1;
        //     arduino.cpu.delayMilliseconds(2);
        // } else if (buttonIsPressed(1)) {
        //     midi_port -|= 1;
        //     arduino.cpu.delayMilliseconds(2);
        // } else if (buttonIsPressed(2)) {
        //     channel +|= 1;
        //     arduino.cpu.delayMilliseconds(2);
        // } else if (buttonIsPressed(3)) {
        //     channel -|= 1;
        //     arduino.cpu.delayMilliseconds(2);
        // }


        index = (index + 1) % running_average_size;
        const raw_value = arduino.gpio.getPinAnalog(1) & 0x3FF;
        const value = @intCast(u7, raw_value >> 3);
        
        running_average[index] = value;
        var average: u16 = 0;
        for (running_average) |e| {
            average += e;
        }
        average /= running_average_size;

        if (last_average != average) {
            last_average = average;
            sendMidiContinousControllPacket(midi_port, channel,
                @intCast(u7, average & 0x7F));
        }
        arduino.cpu.delayMicroseconds(250);

    }
        //     if (average > last_average +| 5 or average < last_average -| 5) {
        //         if (average != 0 and last_average != 0) {
        //             continue;
        //         }
        //     }
            // const value = @intCast(u8, (raw_value * 128) / 1024);
            // writeMidiContinousControllPacket(value);
            // last_average = @intCast(u16, average);
        // }
        // }
        // arduino.cpu.delayMilliseconds(2);
        // arduino.cpu.delayMicroseconds(100);
    // }
}
