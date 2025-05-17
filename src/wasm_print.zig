//!Overrides logFn and panic to log output to JavaScript.
const std = @import("std");
const shared = @import("shared.zig");
pub const PrintType = shared.PrintType;
//Print panic non-asynchronously
pub extern fn JSPrint([*c]const u8, usize, bool) void;
pub fn panic(mesg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    var ebi: usize = 0;
    var error_buffer: [512]u8 = undefined;
    error_buffer[0] = 1;
    error_buffer[1] = @intCast(@intFromEnum(shared.PrintType.err));
    ebi += 4;
    for ("A wasm module has panicked. Panic message:\n'") |ch| {
        error_buffer[ebi] = ch;
        ebi += 1;
    }
    for (0..mesg.len) |i| {
        error_buffer[ebi] = mesg[i];
        ebi += 1;
    }
    for ("'\n") |ch| {
        error_buffer[ebi] = ch;
        ebi += 1;
    }
    error_buffer[2] = @intCast((ebi - 4) & 0x00FF);
    error_buffer[3] = @intCast(((ebi - 4) & 0xFF00) >> 8);
    override_print = error_buffer[0..ebi];
    FlushPrint(false);
    @trap();
}
pub var override_print: ?[]const u8 = null;
pub export fn FlushPrint(mark_full: bool) void {
    if (override_print) |ovp| {
        JSPrint(ovp.ptr, ovp.len, false);
    } else {
        if (wasm_printer.pos != 0) JSPrint(&wasm_printer.buf[0], wasm_printer.pos, mark_full);
        wasm_printer.reset();
    }
}
pub export fn PrintBufferMax() usize {
    return 8192;
}
pub var PrintBufferAutoFlushBytes: usize = 4096;
const PrintBufferT = [PrintBufferMax()]u8;
var wasm_printer = WasmPrinter.init();
///Assuming buf is encoded properly using the comment from `std_options.logFn`
pub const std_options = struct {
    pub const log_level = .debug;
    /// Encodes string as {num_messages (1-byte), X0, X1, ..., Xnum_messages}
    ///
    /// Xn as {print_type (1-byte), num_characters (2-byte, LE), message}
    pub fn logFn(
        comptime l: std.log.Level,
        comptime _: @Type(.enum_literal),
        comptime format: []const u8,
        args: anytype,
    ) void {
        override_print = null;
        if (wasm_printer.pos >= PrintBufferMax() - 3 or wasm_printer.buf[0] == 255)
            FlushPrint(false);
        const pt: PrintType = switch (l) {
            .debug, .info => .log,
            .warn => .warn,
            .err => .err,
        };
        while (true) {
            wasm_printer.buf[wasm_printer.pos] = @intCast(@intFromEnum(pt));
            var num_bytes: u32 = 0;
            wasm_printer.write_ctr = &num_bytes;
            const write_n = wasm_printer.pos + 1;
            wasm_printer.buf[write_n] = 0;
            wasm_printer.buf[write_n + 1] = 0;
            wasm_printer.pos += 3;
            if (std.fmt.format(wasm_printer.writer(), format, args)) {
                wasm_printer.buf[0] += 1;
                wasm_printer.buf[write_n] = @intCast(num_bytes & 0x00FF);
                wasm_printer.buf[write_n + 1] = @intCast((num_bytes & 0xFF00) >> 8);
                if (wasm_printer.pos >= PrintBufferAutoFlushBytes) FlushPrint(false);
                break;
            } else |err| {
                switch (err) {
                    error.NeedsFlush => {
                        wasm_printer.flush_finished();
                    },
                    error.TooFull => {
                        wasm_printer.buf[0] += 1;
                        wasm_printer.buf[write_n] = @intCast(num_bytes & 0x00FF);
                        wasm_printer.buf[write_n + 1] = @intCast((num_bytes & 0xFF00) >> 8);
                        FlushPrint(true);
                        return;
                    },
                }
            }
        }
    }
};
const WasmPrinter = struct {
    const WriteError = error{ TooFull, NeedsFlush };
    const Writer = std.io.Writer(*WasmPrinter, WasmPrinter.WriteError, WasmPrinter.write);
    write_ctr: ?*u32 = null, //Used for write to write the total number of bytes.
    pos: usize = 1,
    buf: PrintBufferT = undefined,
    fn init() WasmPrinter {
        var wp: WasmPrinter = .{};
        wp.buf[0] = 0; //0th byte represents the number of messages to be added to js console print.
        return wp;
    }
    /// Copied from std std.io.BufferedWriter.
    fn write(self: *@This(), bytes: []const u8) WriteError!usize {
        if (self.pos + bytes.len > self.buf.len) { //Message too long ( Over PrintBufferMax() )
            @memcpy(self.buf[self.pos..], bytes[0 .. self.buf.len - self.pos]);
            self.write_ctr.?.* += @intCast(bytes.len - self.pos);
            self.pos = self.buf.len;
            return WriteError.TooFull;
        }
        @memcpy(self.buf[self.pos..(self.pos + bytes.len)], bytes);
        self.write_ctr.?.* += @intCast(bytes.len);
        self.pos += bytes.len;
        return bytes.len;
    }
    fn flush_finished(self: *@This()) void {
        const old_pos = self.pos;
        while (self.buf[self.pos - 1] != '\n') : (self.pos -= 1) { //Exclude unfinished \n terminated strings if possible.
            if (self.pos == 1) {
                self.pos = old_pos;
                break;
            }
        }
        FlushPrint(false);
    }
    fn reset(self: *@This()) void {
        self.pos = 1;
        self.buf[0] = 0;
    }
    fn writer(self: *@This()) Writer {
        return .{ .context = self };
    }
};
pub fn WasmError(err: anyerror) noreturn {
    FlushPrint(false);
    var ebi: usize = 0;
    var error_buffer: [512]u8 = undefined;
    error_buffer[0] = 1;
    error_buffer[1] = @intCast(@intFromEnum(shared.PrintType.err));
    ebi += 4;
    for ("A Wasm module has an uncaught error:\n'") |ch| {
        error_buffer[ebi] = ch;
        ebi += 1;
    }
    for (0..@errorName(err).len) |i| {
        error_buffer[ebi] = @errorName(err)[i];
        ebi += 1;
    }
    for ("'\n") |ch| {
        error_buffer[ebi] = ch;
        ebi += 1;
    }
    error_buffer[2] = @intCast((ebi - 4) & 0x00FF);
    error_buffer[3] = @intCast(((ebi - 4) & 0xFF00) >> 8);
    override_print = error_buffer[0..ebi];
    FlushPrint(false);
    @trap();
}
