const std = @import("std");
pub const SortedIntListType = enum { lt, gt };
pub fn SortedIntList(comptime IntT: type, comptime list_type: SortedIntListType) type {
    return SortedList(IntT, IntTCmp(IntT, list_type));
}
pub fn IntTCmp(IntT: type, comptime list_type: SortedIntListType) type {
    return struct {
        pub fn lt(a: IntT, b: IntT) bool {
            return if (list_type == .lt) a < b else a > b;
        }
        pub fn eq(a: IntT, b: IntT) bool {
            return a == b;
        }
    };
}
pub fn SortedList(comptime T: type, comptime Cmp: anytype) type {
    return struct {
        pub const empty: @This() = .{ .list = .empty };
        list: std.ArrayListUnmanaged(T),
        pub fn insert_unique(self: *@This(), allocator: std.mem.Allocator, value: T) !bool {
            if (self.list.items.len != 0) {
                var low_i: usize = 0;
                var high_i: usize = self.list.items.len - 1;
                var mid_i = high_i / 2;
                while (high_i >= low_i) : (mid_i = (high_i + low_i) / 2) {
                    if (Cmp.eq(value, self.list.items[mid_i])) return false; //Don't insert duplicates
                    if (Cmp.lt(self.list.items[mid_i], value)) {
                        low_i = mid_i + 1;
                    } else {
                        if (mid_i != 0) {
                            high_i = mid_i - 1;
                        } else { //Insert at left end
                            try self.list.insert(allocator, 0, value);
                            return true;
                        }
                    }
                }
                try self.list.insert(allocator, mid_i + 1, value); //Insert at right of mid_i
                return true;
            }
            try self.list.append(allocator, value);
            return true;
        }
        pub fn remove(self: *@This(), value: T) !void {
            if (self.list.items.len == 0) return;
            var low_i: usize = 0;
            var high_i: usize = self.list.items.len - 1;
            var mid_i = high_i / 2;
            while (high_i >= low_i) : (mid_i = (high_i + low_i) / 2) {
                if (Cmp.eq(value, self.list.items[mid_i])) {
                    try self.list.orderedRemove(mid_i);
                    return;
                }
                if (Cmp.lt(self.list.items[mid_i], value)) {
                    low_i = mid_i + 1;
                } else {
                    if (mid_i != 0) {
                        high_i = mid_i - 1;
                    } else return;
                }
            }
            return;
        }
        pub fn search(self: @This(), value: T) ?usize {
            if (self.list.items.len == 0) return null;
            var low_i: usize = 0;
            var high_i: usize = self.list.items.len - 1;
            var mid_i = high_i / 2;
            while (high_i >= low_i) : (mid_i = (high_i + low_i) / 2) {
                if (Cmp.eq(value, self.list.items[mid_i])) return mid_i;
                if (Cmp.lt(self.list.items[mid_i], value)) {
                    low_i = mid_i + 1;
                } else {
                    if (mid_i != 0) {
                        high_i = mid_i - 1;
                    } else return null;
                }
            }
            return null;
        }
        pub fn exists(self: @This(), value: T) bool {
            if (self.list.items.len == 0) return false;
            var low_i: usize = 0;
            var high_i: usize = self.list.items.len - 1;
            var mid_i = high_i / 2;
            while (high_i >= low_i) : (mid_i = (high_i + low_i) / 2) {
                if (Cmp.eq(value, self.list.items[mid_i])) return true;
                if (Cmp.lt(self.list.items[mid_i], value)) {
                    low_i = mid_i + 1;
                } else {
                    if (mid_i != 0) {
                        high_i = mid_i - 1;
                    } else return false;
                }
            }
            return false;
        }
        pub fn eq_slice(self: @This(), slice: []const T) bool {
            return std.mem.eql(T, self.list.items, slice);
        }
        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            self.list.deinit(allocator);
        }
    };
}
test SortedList {
    var sl: SortedIntList(u32, .lt) = .empty;
    defer sl.deinit(std.testing.allocator);
    try std.testing.expect(sl.eq_slice(&.{}));
    try std.testing.expect(try sl.insert_unique(std.testing.allocator, 3));
    try std.testing.expect(sl.eq_slice(&.{3}));
    try std.testing.expect(try sl.insert_unique(std.testing.allocator, 1));
    try std.testing.expect(sl.eq_slice(&.{ 1, 3 }));
    try std.testing.expect(try sl.insert_unique(std.testing.allocator, 0));
    try std.testing.expect(sl.eq_slice(&.{ 0, 1, 3 }));
    try std.testing.expect(try sl.insert_unique(std.testing.allocator, 2));
    try std.testing.expect(sl.eq_slice(&.{ 0, 1, 2, 3 }));
    var int_t: u32 = 0;
    while (int_t < sl.list.items.len) : (int_t += 1) { //Duplicate test
        try std.testing.expect(!try sl.insert_unique(std.testing.allocator, int_t));
        try std.testing.expect(sl.eq_slice(&.{ 0, 1, 2, 3 }));
    }
    try std.testing.expect(try sl.insert_unique(std.testing.allocator, 4));
    try std.testing.expect(sl.eq_slice(&.{ 0, 1, 2, 3, 4 }));
    int_t = 0;
    while (int_t < sl.list.items.len) : (int_t += 1) { //Duplicate test #2
        try std.testing.expect(!try sl.insert_unique(std.testing.allocator, int_t));
        try std.testing.expect(sl.eq_slice(&.{ 0, 1, 2, 3, 4 }));
    }
}
