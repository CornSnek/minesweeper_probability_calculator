const std = @import("std");
const WasmError = @import("wasm_print.zig").WasmError;
const sorted_list = @import("sorted_list.zig");
const allocator = @import("wasm_main.zig").wasm_allocator;
var JSAllocList: sorted_list.SortedList([]u8, struct {
    pub fn lt(a: []const u8, b: []const u8) bool {
        return @intFromPtr(a.ptr) < @intFromPtr(b.ptr);
    }
    pub fn eq(a: []const u8, b: []const u8) bool {
        return a.ptr == b.ptr;
    }
}) = .empty;
pub export fn WasmListAllocs() void {
    std.log.debug("List of external memory slices (pointer value is decimal):\n", .{});
    for (JSAllocList.list.items) |slice| {
        std.log.debug("pointer: {} len: {}\n", .{ @intFromPtr(slice.ptr), slice.len });
    }
}
pub export fn WasmAlloc(size_bytes: usize) [*c]u8 {
    if (size_bytes == 0) @panic("size_bytes must be greater than 0");
    const alloc_slice = allocator.alloc(u8, size_bytes) catch |e| WasmError(e);
    std.debug.assert(JSAllocList.insert_unique(allocator, alloc_slice) catch |e| WasmError(e));
    return alloc_slice.ptr;
}
pub export fn WasmFree(ptr: [*c]u8) void {
    const slice_i = JSAllocList.search(ptr[0..0]);
    if (slice_i) |i| {
        allocator.free(JSAllocList.list.orderedRemove(i));
        return;
    }
    @panic("Memory is not valid or is already free");
}
pub export fn WasmFreeAll() void {
    for (JSAllocList.list.items) |slice|
        allocator.free(slice);
    JSAllocList.list.clearRetainingCapacity();
}
pub fn slice_to_js(slice: []u8) !void {
    std.debug.assert(try JSAllocList.insert_unique(allocator, slice));
}
