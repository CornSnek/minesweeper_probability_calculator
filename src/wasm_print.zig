//!Overrides logFn and panic to log output to JavaScript.
const std = @import("std");
const shared = @import("shared.zig");
pub const PrintType = shared.PrintType;
//Print panic non-asynchronously
pub extern fn JSPrint([*c]const u8, usize, bool) void;
pub fn panic(mesg: []const u8, _: ?usize) noreturn {
    FlushPrint(false);
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
        if (wasm_printer.writer.end != 0) JSPrint(&wasm_printer.writer.buffer[0], wasm_printer.writer.end, mark_full);
        wasm_printer.reset();
    }
}
pub export fn PrintBufferMax() usize {
    return 8192;
}
pub var PrintBufferAutoFlushBytes: usize = 4096;
const PrintBufferT = [PrintBufferMax()]u8;
//0th byte represents the number of messages to be added to js console print.
var wp_buf: PrintBufferT = [1]u8{0} ++ [1]u8{undefined} ** (PrintBufferMax() - 1);
var wasm_printer = WasmPrinter.init(&wp_buf);
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
        if (wasm_printer.writer.end >= PrintBufferMax() - 3 or wasm_printer.writer.buffer[0] == 255)
            FlushPrint(false);
        const pt: PrintType = switch (l) {
            .debug, .info => .log,
            .warn => .warn,
            .err => .err,
        };
        wasm_printer.init_message(pt);
        if (wasm_printer.writer.print(format, args)) {
            wasm_printer.end_message();
        } else |_| unreachable;
    }
};
const WasmPrinter = struct {
    use_pt: PrintType,
    old_end: usize,
    write_n: usize,
    writer: std.Io.Writer,
    fn init(buf: []u8) WasmPrinter {
        return .{
            .use_pt = .log,
            .old_end = 0,
            .write_n = 0,
            .writer = .{
                .buffer = buf,
                .end = 1, //0th byte represents the number of messages to be added to js console print.
                .vtable = &.{
                    .drain = drain,
                    .flush = flush_to_js,
                },
            },
        };
    }
    fn init_message(wp: *WasmPrinter, pt: PrintType) void {
        wp.use_pt = pt;
        wp.writer.buffer[wp.writer.end] = @intCast(@intFromEnum(pt));
        wp.write_n = wp.writer.end + 1;
        wp.writer.buffer[wp.write_n] = 0;
        wp.writer.buffer[wp.write_n + 1] = 0;
        wp.writer.end += 3;
        wp.old_end = wp.writer.end;
    }
    fn end_message(wp: *WasmPrinter) void {
        wp.writer.buffer[0] += 1;
        const end_diff: u32 = @truncate(wp.writer.end - wp.old_end);
        wp.writer.buffer[wp.write_n] = @intCast(end_diff & 0x00FF);
        wp.writer.buffer[wp.write_n + 1] = @intCast((end_diff & 0xFF00) >> 8);
        if (wp.writer.end >= PrintBufferAutoFlushBytes) FlushPrint(false);
    }
    ///TODO: Check if drain works as intended.
    fn drain(w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
        const wp: *WasmPrinter = @fieldParentPtr("writer", w);
        if (data.len == 0) return 0;
        var total_bytes: usize = 0;
        for (data[0 .. data.len - 1]) |bytes| {
            try wp.write_bytes(bytes);
            total_bytes += @min(bytes.len, w.buffer.len);
        }
        const pattern = data[data.len - 1];
        switch (pattern.len) {
            0 => {},
            1 => {
                var rem = splat;
                while (rem > 0) {
                    const dest = w.buffer[w.end..];
                    if (dest.len == 0) {
                        try w.flush();
                        continue;
                    }
                    const len = @min(dest.len, rem);
                    @memset(dest[0..len], pattern[0]);
                    w.end += len;
                    total_bytes += len;
                    rem -= len;
                }
            },
            else => {
                var rem = splat;
                while (rem > 0) {
                    const dest = w.buffer[w.end..];
                    if (dest.len == 0) {
                        try w.flush();
                        continue;
                    }
                    const len = @min(dest.len, pattern.len);
                    @memcpy(dest[0..len], pattern[0..len]);
                    w.end += len;
                    total_bytes += len;
                    if (len < pattern.len) {
                        try w.flush();
                        continue;
                    }
                    rem -= 1;
                }
            },
        }
        return total_bytes;
    }
    fn write_bytes(wp: *WasmPrinter, bytes: []const u8) std.Io.Writer.Error!void {
        var rem_bytes = bytes;
        if (bytes.len > wp.writer.buffer.len) { //Truncate if too many bytes from message.
            const trunc_buf = bytes[0..wp.writer.buffer.len];
            @memcpy(wp.writer.buffer[0..trunc_buf.len], trunc_buf);
            wp.writer.end = trunc_buf.len;
            wp.end_message();
            FlushPrint(true);
            wp.init_message(wp.use_pt);
            return;
        }
        while (rem_bytes.len > 0) { //If buffer will be full after bytes message.
            const dest = wp.writer.buffer[wp.writer.end..];
            const len = @min(rem_bytes.len, dest.len);
            @memcpy(dest[0..len], rem_bytes[0..len]);
            wp.writer.end += len;
            rem_bytes = rem_bytes[len..];
            if (rem_bytes.len > 0) { //Set new message after flushing the full buffer.
                wp.end_message();
                try flush_to_js(&wp.writer);
                wp.init_message(wp.use_pt);
            }
        }
    }
    fn flush_to_js(w: *std.Io.Writer) std.Io.Writer.Error!void {
        const old_end = w.end;
        while (w.buffer[w.end - 1] != '\n') : (w.end -= 1) { //Exclude unfinished \n terminated strings if possible.
            if (w.end == 1) {
                w.end = old_end;
                break;
            }
        }
        FlushPrint(false);
    }
    fn reset(self: *@This()) void {
        self.writer.end = 1;
        self.writer.buffer[0] = 0;
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
