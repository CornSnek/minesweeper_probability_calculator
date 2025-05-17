const std = @import("std");
pub const std_options_impl = if (@import("builtin").os.tag != .freestanding) NonWasmLog else WasmLog;
const NonWasmLog = struct {
    pub fn logFn(
        comptime _: std.log.Level,
        comptime _: @Type(.EnumLiteral),
        comptime format: []const u8,
        args: anytype,
    ) void {
        const stderr = std.io.getStdErr().writer();
        var bw = std.io.bufferedWriter(stderr);
        const writer = bw.writer();
        std.debug.lockStdErr();
        defer std.debug.unlockStdErr();
        nosuspend {
            writer.print(format, args) catch return;
            bw.flush() catch return;
        }
    }
};
const WasmLog = @import("wasm_print.zig").std_options;
