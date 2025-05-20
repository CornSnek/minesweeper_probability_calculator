const std = @import("std");
///Arbitrary big number in little-endian.
pub const BigUInt = struct {
    bytes: std.ArrayListUnmanaged(u8),
    pub fn init(allocator: std.mem.Allocator, init_num: u8) !BigUInt {
        var bytes: std.ArrayListUnmanaged(u8) = .empty;
        try bytes.append(allocator, init_num);
        return .{ .bytes = bytes };
    }
    pub fn init_int(allocator: std.mem.Allocator, init_num: anytype) !BigUInt {
        const IntType = @typeInfo(@TypeOf(init_num));
        if (IntType != .int) @compileError("init_num should be an integer");
        var bytes: std.ArrayListUnmanaged(u8) = .empty;
        const init_num_little = std.mem.nativeToLittle(@TypeOf(init_num), init_num);
        try bytes.appendNTimes(allocator, undefined, IntType.int.bits / 8);
        @memcpy(bytes.items, std.mem.asBytes(&init_num_little)[0 .. IntType.int.bits / 8]);
        return .{ .bytes = bytes };
    }
    pub fn clone(self: BigUInt, allocator: std.mem.Allocator) !BigUInt {
        return .{ .bytes = try self.bytes.clone(allocator) };
    }
    pub fn add_one(self: *BigUInt, allocator: std.mem.Allocator) !void {
        for (0..self.bytes.items.len) |i| {
            self.bytes.items[i], const carry = @addWithOverflow(self.bytes.items[i], 1);
            if (carry == 0) {
                return;
            } else {
                if (i == self.bytes.items.len - 1) {
                    try self.bytes.append(allocator, 1);
                    return;
                }
            }
        }
    }
    pub fn add(self: *BigUInt, allocator: std.mem.Allocator, by_bui: BigUInt) !void {
        if (by_bui.bytes.items.len > self.bytes.items.len)
            try self.bytes.appendNTimes(allocator, 0, by_bui.bytes.items.len - self.bytes.items.len);
        var carry: u1 = 0;
        for (0..self.bytes.items.len) |i| {
            self.bytes.items[i], carry = @addWithOverflow(self.bytes.items[i], carry);
            const by_bui_byte = if (i < by_bui.bytes.items.len) by_bui.bytes.items[i] else 0; //0 if out of bounds. self may be repeated bytes of FF so carry will keep adding...
            self.bytes.items[i], const carry2 = @addWithOverflow(self.bytes.items[i], by_bui_byte);
            carry |= carry2; //Case 1: carry made it overflow from 0xFF to 0x00, making carry2 always 0. Case 2: carry did not overflow, and carry2 might
        }
        if (carry == 1)
            try self.bytes.append(allocator, 1);
    }
    pub fn multiply_byte(self: *BigUInt, allocator: std.mem.Allocator, by: u8) !void {
        var carry: u8 = 0;
        for (0..self.bytes.items.len) |i| {
            const product: u16 = @as(u16, @intCast(self.bytes.items[i])) * by + carry;
            self.bytes.items[i] = @intCast(product & 0xFF);
            carry = @intCast(product >> 8);
        }
        if (carry != 0)
            try self.bytes.append(allocator, carry);
    }
    ///Returns remainder, but null if by == 0
    pub fn divide_byte(self: *BigUInt, by: u8) ?u8 {
        if (by == 0) return null;
        var remainder: u16 = 0;
        const len = self.bytes.items.len;
        for (0..len) |i| {
            const acc: u16 = (remainder << 8) | self.bytes.items[len - 1 - i];
            self.bytes.items[len - 1 - i] = @truncate(acc / by);
            remainder = acc % by;
        }
        return @truncate(remainder);
    }
    ///Switch back and forth in adding/multiplying
    const MultiplyResult = union(enum) {
        init: BigUInt,
        sum_second: [2]BigUInt,
        sum_first: [2]BigUInt,
        fn deinit(self: *MultiplyResult, allocator: std.mem.Allocator) void {
            switch (self.*) {
                .init => |*bui| bui.deinit(allocator),
                inline else => |*arr| {
                    arr[0].deinit(allocator);
                    arr[1].deinit(allocator);
                },
            }
        }
    };
    pub fn multiply(self: *BigUInt, allocator: std.mem.Allocator, by_bui: BigUInt) !void {
        var mr: MultiplyResult = .{ .init = try self.clone(allocator) };
        errdefer mr.deinit(allocator);
        try mr.init.multiply_byte(allocator, by_bui.bytes.items[0]);
        for (1..by_bui.bytes.items.len) |i| {
            const by_bui_byte = by_bui.bytes.items[i];
            switch (mr) {
                .init => |*bui| {
                    mr = .{ .sum_second = .{ bui.*, try self.clone(allocator) } };
                    try mr.sum_second[1].shift_bytes_left(allocator, i);
                    try mr.sum_second[1].multiply_byte(allocator, by_bui_byte);
                },
                .sum_second => |*bui_arr| {
                    try bui_arr[1].add(allocator, bui_arr[0]);
                    bui_arr[0].bytes.clearRetainingCapacity();
                    try bui_arr[0].bytes.appendSlice(allocator, self.bytes.items);
                    try bui_arr[0].shift_bytes_left(allocator, i);
                    try bui_arr[0].multiply_byte(allocator, by_bui_byte);
                    mr = .{ .sum_first = bui_arr.* };
                },
                .sum_first => |*bui_arr| {
                    try bui_arr[0].add(allocator, bui_arr[1]);
                    bui_arr[1].bytes.clearRetainingCapacity();
                    try bui_arr[1].bytes.appendSlice(allocator, self.bytes.items);
                    try bui_arr[1].shift_bytes_left(allocator, i);
                    try bui_arr[1].multiply_byte(allocator, by_bui_byte);
                    mr = .{ .sum_second = bui_arr.* };
                },
            }
        }
        switch (mr) {
            .init => |*bui| bui.deinit(allocator),
            .sum_first => |*bui_arr| {
                try bui_arr[0].add(allocator, bui_arr[1]);
                bui_arr[1].deinit(allocator);
                self.deinit(allocator);
                self.bytes = bui_arr[0].bytes;
            },
            .sum_second => |*bui_arr| {
                try bui_arr[1].add(allocator, bui_arr[0]);
                bui_arr[0].deinit(allocator);
                self.deinit(allocator);
                self.bytes = bui_arr[1].bytes;
            },
        }
    }
    ///Pad with zeroes
    pub fn pad(self: *BigUInt, allocator: std.mem.Allocator, min_bytes: usize) !void {
        if (min_bytes > self.bytes.items.len) {
            try self.bytes.ensureTotalCapacityPrecise(allocator, min_bytes);
            const old_len: usize = self.bytes.items.len;
            self.bytes.items.len = min_bytes;
            for (old_len..self.bytes.items.len) |i| {
                self.bytes.items[i] = 0;
            }
        }
    }
    ///Trim most-significant trailing zeroes byte excluding least-significant byte.
    pub fn trim(self: *BigUInt) void {
        var i = self.bytes.items.len;
        while (i > 1) {
            i -= 1;
            if (self.bytes.items[i] == 0) {
                self.bytes.items.len -= 1;
            } else break;
        }
    }
    pub fn bit(self: BigUInt, offset: usize) bool {
        return self.bytes.items[offset / 8] & (@as(u8, 1) << @as(u3, @intCast(offset % 8))) != 0;
    }
    pub fn set(self: BigUInt, offset: usize) void {
        self.bytes.items[offset / 8] |= (@as(u8, 1) << @as(u3, @intCast(offset % 8)));
    }
    pub fn shift_bytes_left(self: *BigUInt, allocator: std.mem.Allocator, by: usize) !void {
        const old_len = self.bytes.items.len;
        try self.bytes.appendNTimes(allocator, undefined, by);
        std.mem.copyBackwards(u8, self.bytes.items[by..], self.bytes.items[0..old_len]);
        @memset(self.bytes.items[0..by], 0);
    }
    pub fn format(self: BigUInt, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.writeAll("BigNumber{ ");
        for (0..self.bytes.items.len) |i| {
            const b = self.bytes.items[i];
            try std.fmt.formatIntValue(b, fmt, options, writer);
            if (i != self.bytes.items.len - 1) try writer.writeAll(", ");
        }
        try writer.writeAll(" }");
    }
    pub fn order(self: BigUInt, other: BigUInt) std.math.Order {
        const self_len = self.bytes.items.len;
        if (self_len > other.bytes.items.len) {
            return std.math.Order.gt;
        } else if (other.bytes.items.len > self_len) {
            return std.math.Order.lt;
        }
        var cmp_self_byte: u8 = 0;
        var cmp_other_byte: u8 = 0;
        for (0..self_len) |i| {
            const rev_i = self_len - 1 - i;
            cmp_self_byte = self.bytes.items[rev_i];
            cmp_other_byte = other.bytes.items[rev_i];
            if (cmp_self_byte != cmp_other_byte) break;
        }
        return std.math.order(cmp_self_byte, cmp_other_byte);
    }
    //From std.math.big.int.Const.toFloat
    pub fn to_float(self: BigUInt, comptime FType: type) FType {
        var result: f128 = 0;
        var i = self.bytes.items.len;
        while (i != 0) { //Multiply each byte by 256 exponentially.
            i -= 1;
            result = @mulAdd(f128, std.math.maxInt(u8) + 1, result, @floatFromInt(self.bytes.items[i]));
        }
        return @floatCast(result);
    }
    const ArrayToU32 = extern union {
        as_bytes: [4]u8,
        as_u32: u32,
    };
    pub fn pop_count(self: BigUInt) usize {
        var sum: usize = 0;
        var i: usize = 0;
        const len = self.bytes.items.len;
        var atu32: ArrayToU32 = undefined;
        //Population count that sums up each 4 bytes (u32), then the remainder bytes.
        while (i + 4 <= len) {
            @memcpy(&atu32.as_bytes, self.bytes.items[i .. i + 4]);
            sum += @popCount(atu32.as_u32);
            i += 4;
        }
        if (i == len) return sum;
        atu32.as_u32 = 0;
        @memcpy((&atu32.as_bytes).ptr, self.bytes.items[i..len]);
        sum += @popCount(atu32.as_u32);
        return sum;
    }
    pub fn is_zero(self: BigUInt) bool {
        return std.mem.allEqual(u8, self.bytes.items, 0);
    }
    pub fn as_string(self: BigUInt, allocator: std.mem.Allocator) !std.ArrayListUnmanaged(u8) {
        var digits: std.ArrayListUnmanaged(u8) = .empty;
        errdefer digits.deinit(allocator);
        var value = try self.clone(allocator);
        defer value.deinit(allocator);
        while (!value.is_zero()) : (value.trim())
            try digits.append(allocator, value.divide_byte(10).? + '0');
        std.mem.reverse(u8, digits.items);
        return digits;
    }
    pub fn deinit(self: *BigUInt, allocator: std.mem.Allocator) void {
        self.bytes.deinit(allocator);
    }
};
const t_allocator = std.testing.allocator;
test "BigUInt" {
    var bui: BigUInt = try .init(t_allocator, 100);
    defer bui.deinit(t_allocator);
    try bui.multiply_byte(t_allocator, 255);
    try bui.multiply_byte(t_allocator, 255);
    try bui.multiply_byte(t_allocator, 255);
    try bui.multiply_byte(t_allocator, 255);
    try bui.multiply_byte(t_allocator, 255);
    try bui.multiply_byte(t_allocator, 255);
    try bui.multiply_byte(t_allocator, 255);
    var bui2: BigUInt = try .init(t_allocator, 100);
    defer bui2.deinit(t_allocator);
    try bui2.multiply_byte(t_allocator, 255);
    std.debug.print("{} {d} {}\n", .{ bui.order(bui2), bui.to_float(f64), bui.pop_count() });
    var bui_str = try bui.as_string(t_allocator);
    defer bui_str.deinit(t_allocator);
    std.debug.print("{s}\n", .{bui_str.items});
}
