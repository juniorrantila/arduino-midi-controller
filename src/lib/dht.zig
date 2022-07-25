const gpio = @import("../gpio.zig");
const cpu = @import("../cpu.zig");

// hacked from
// from  https://github.com/RobTillaart/Arduino/tree/master/libraries/DHTlib
// and the spec: https://www.gotronic.fr/pj-1052.pdf

// clang11? doesn't seem to like error unions...
//  --> hack it for now
const HackError = enum(u8) {
    OK,
    BAD_CHECKSUM,
    NO_CONNECTION,
    NO_ACK,
    INTERRUPTED,
};

pub const Readout = struct { humidity_x10: i16, temperature_x10: i16, err: HackError }; // fixedpoint values. divide by 10 for the actual flaot value

pub fn DHT22(comptime sensor_data_pin: u8) type {
    return struct {
        pub fn read() Readout {
            const r = readSensor(sensor_data_pin);
            if (r.err != .OK) { // HackError
                return .{ .humidity_x10 = 0, .temperature_x10 = 0, .err = r.err };
            }
            return convertRawSensor(r.raw);
        }

        fn convertRawSensor(raw: u40) Readout {
            var sensor: packed union { // little endian
                raw: u40,
                bytes: [5]u8,
                values: packed struct {
                    checksum: u8,
                    temp: u15,
                    temp_sign: u1,
                    hum: u16,
                },
            } = .{ .raw = raw };

            const checksum = sensor.bytes[4] +% sensor.bytes[1] +% sensor.bytes[2] +% sensor.bytes[3];
            if (checksum != sensor.values.checksum)
                return .{ .humidity_x10 = 0, .temperature_x10 = 0, .err = .BAD_CHECKSUM };

            return Readout{
                .humidity_x10 = @intCast(i16, sensor.values.hum),
                .temperature_x10 = if (sensor.values.temp_sign != 0) -@as(i16, sensor.values.temp) else @as(i16, sensor.values.temp),
                .err = .OK,
            };
        }

        const TIMEOUT_100us = (100 * cpu.CPU_FREQ / 1_000_000) / 4; // ~4 cycles per loop
        fn waitPinState(comptime pin: u8, state: gpio.PinState, timeout: u16) bool {
            var loop_count: u16 = timeout;
            while (loop_count > 0) : (loop_count -= 1) {
                if (gpio.getPin(pin) == state)
                    return true;
            }
            return false;
        }

        fn readSensor(comptime pin: u8) struct { raw: u40 = 0, err: HackError = .OK } {
            const wakeup_delay = 1;
            const leading_zero_bits = 6;

            // single wire protocol

            // SEND THE QUERY and wait for the ACK
            {
                // "host pulls low >1ms"
                gpio.setMode(pin, .output);
                gpio.setPin(pin, .low);
                cpu.delayMicroseconds(wakeup_delay * 1000); // 1ms

                // "host pulls up and wait for sensor response"
                gpio.setPin(pin, .high);
                gpio.setMode(pin, .input_pullup);

                if (!waitPinState(pin, .low, TIMEOUT_100us * 2)) return .{ .err = .NO_CONNECTION }; // 40+80us
                if (!waitPinState(pin, .high, TIMEOUT_100us)) return .{ .err = .NO_ACK }; // 80us
                if (!waitPinState(pin, .low, TIMEOUT_100us)) return .{ .err = .NO_ACK }; // 80us
            }

            // READ THE OUTPUT - 40 BITS
            var zero_loop_len: u16 = TIMEOUT_100us / 4; // autocalibrate knowing there are leading zeros  (not checked with an oscilloscope or anything)
            var result: u40 = 0;
            var bit_idx: u8 = 0;
            while (bit_idx < 40) : (bit_idx += 1) {
                if (!waitPinState(pin, .high, TIMEOUT_100us)) return .{ .err = .INTERRUPTED }; // 50us

                // measure time to get low:
                const duration = blk: {
                    var loop_count: u16 = TIMEOUT_100us;
                    while (loop_count > 0) : (loop_count -= 1) {
                        if (gpio.getPin(pin) == .low)
                            break :blk (TIMEOUT_100us - loop_count);
                    }
                    return .{ .err = .INTERRUPTED }; // 70us
                };

                if (bit_idx < leading_zero_bits) {
                    if (zero_loop_len < duration)
                        zero_loop_len = duration; // max observed time to get zero
                } else {
                    const is_one = duration > zero_loop_len; // exceeded zero duration
                    result = (result << 1) | @boolToInt(is_one);
                }
            }

            return .{ .raw = result };
        }
    };
}
