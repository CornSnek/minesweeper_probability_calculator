const std = @import("std");
pub fn EqualBitsOnly(comptime IntT: type, comptime bits: u16) void {
    const error_msg = std.fmt.comptimePrint("Type {s} must be an integer with exactly {} bits", .{ @typeName(IntT), bits });
    switch (@typeInfo(IntT)) {
        .Enum => |e| {
            if (@typeInfo(e.tag_type).Int.bits != bits) @compileError(error_msg);
        },
        .Int => |i| {
            if (i.bits != bits) @compileError(error_msg);
        },
        .Union => |u| {
            if (u.tag_type) |utt| {
                if (@typeInfo(utt).Int.bits != bits) @compileError(error_msg);
            } else @compileError(error_msg);
        },
        else => @compileError(error_msg),
    }
}
pub const WaitStatus = enum(u32) { ok, not_equal, timed_out };
pub fn atomic_wait32(Int32T: type, address: *Int32T, expected_value: Int32T, timeout_ns: i64) WaitStatus {
    comptime EqualBitsOnly(Int32T, 32);
    return @enumFromInt(asm (
        \\local.get %[addr]
        \\local.get %[ev]
        \\local.get %[tns]
        \\memory.atomic.wait32 0
        \\local.set %[wait_status]
        : [wait_status] "=r" (-> u32),
        : [addr] "r" (address),
          [ev] "r" (expected_value),
          [tns] "r" (timeout_ns),
    ));
}
pub fn atomic_wait64(Int64T: type, address: *Int64T, expected_value: Int64T, timeout_ns: i64) WaitStatus {
    comptime EqualBitsOnly(Int64T, 64);
    return @enumFromInt(asm (
        \\local.get %[addr]
        \\local.get %[ev]
        \\local.get %[tns]
        \\memory.atomic.wait64 0
        \\local.set %[wait_status]
        : [wait_status] "=r" (-> u32),
        : [addr] "r" (address),
          [ev] "r" (expected_value),
          [tns] "r" (timeout_ns),
    ));
}
pub fn atomic_notify32(Int32T: type, address: *Int32T, num_threads_awaken: i32) u32 {
    comptime EqualBitsOnly(Int32T, 32);
    return asm (
        \\local.get %[addr]
        \\local.get %[nta]
        \\memory.atomic.notify 0
        \\local.set %[num_awoken]
        : [num_awoken] "=r" (-> u32),
        : [addr] "r" (address),
          [nta] "r" (num_threads_awaken),
    );
}
pub fn atomic_notify64(Int64T: type, address: *Int64T, num_threads_awaken: i32) u32 {
    comptime EqualBitsOnly(Int64T, 64);
    return asm (
        \\local.get %[addr]
        \\local.get %[nta]
        \\memory.atomic.notify 0
        \\local.set %[num_awoken]
        : [num_awoken] "=r" (-> u32),
        : [addr] "r" (address),
          [nta] "r" (num_threads_awaken),
    );
}
