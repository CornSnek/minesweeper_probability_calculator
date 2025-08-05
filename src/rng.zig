const std = @import("std");
const allocator = @import("root").wasm_allocator;
const CalculatedMap = @import("root").CalculatedMap;
const wasm_jsalloc = @import("wasm_jsalloc.zig");
const StringSlice = @import("shared.zig").StringSlice;
var cm: CalculatedMap = .empty;
var prng: std.Random.Xoshiro256 = .init(0);
pub export fn InitRNGSeed(seed: u64) void {
    prng.seed(seed);
}
var mine_board: std.ArrayListUnmanaged(u8) = .{};
var mine_board_ext: StringSlice = undefined;
pub export fn GetMineBoard() [*c]StringSlice {
    mine_board_ext = .{ .ptr = mine_board.items.ptr, .len = mine_board.items.len };
    return &mine_board_ext;
}
var left_click_board: std.ArrayListUnmanaged(u8) = .{}; //TODO
var lcb_ext: StringSlice = undefined;
pub export fn GetLeftClickBoard() [*c]StringSlice {
    lcb_ext = .{ .ptr = left_click_board.items.ptr, .len = left_click_board.items.len };
    return &lcb_ext;
}
var right_click_board: std.ArrayListUnmanaged(u8) = .{}; //TODO
var rcb_ext: StringSlice = undefined;
pub export fn GetRightClickBoard() [*c]StringSlice {
    rcb_ext = .{ .ptr = right_click_board.items.ptr, .len = right_click_board.items.len };
    return &rcb_ext;
}
fn clear_board() void {
    mine_board.clearRetainingCapacity();
    left_click_board.clearRetainingCapacity();
    right_click_board.clearRetainingCapacity();
}
var mine_seed: std.ArrayListUnmanaged(u8) = .{};
var mine_seed_ext: StringSlice = undefined;
pub export fn GetMineSeed() [*c]StringSlice {
    mine_seed_ext = .{ .ptr = mine_seed.items.ptr, .len = mine_seed.items.len };
    return &mine_seed_ext;
}
///Length is (width * height + 7) / 8 for javascript
pub export fn MinesweeperInitEmpty(num_mines: u32, width: u32, height: u32, safe_click: u32) void {
    const wtimesh = width * height;
    std.debug.assert(num_mines <= width * height and wtimesh != 0);
    clear_board();
    if (wtimesh != num_mines) {
        mine_board.appendNTimes(allocator, 0, (wtimesh + 7) / 8) catch allocation_error();
        var mines_left: u32 = num_mines;
        while (mines_left != 0) {
            const add_i = prng.random().uintLessThan(usize, wtimesh);
            const byte_i = add_i / 8;
            const bit_i: u3 = @truncate(add_i % 8);
            const mask: u8 = (@as(u8, 1) << bit_i);
            if (mine_board.items[byte_i] & mask == 0) {
                if (wtimesh != 1 and safe_click == add_i) continue;
                mine_board.items[byte_i] |= mask;
                mines_left -= 1;
            }
        }
    } else {
        mine_board.appendNTimes(allocator, std.math.maxInt(u8), (wtimesh + 7) / 8) catch allocation_error();
    }
    std.log.debug("[ ", .{});
    for (mine_board.items) |c| {
        std.log.debug("{x}, ", .{c});
    }
    std.log.debug(" ]\n", .{});
    mine_seed.clearRetainingCapacity();
    write_mine_seed(width, height) catch allocation_error();
    std.log.debug("{s}\n", .{mine_seed.items});
    @import("wasm_print.zig").FlushPrint(false);
}
fn write_mine_seed(width: u32, height: u32) !void {
    const writer = mine_seed.writer(allocator);
    try writer.print("{}x{}, ", .{ width, height });
    try writer.writeAll("m=");
    for (mine_board.items) |ch| try writer.print("{x:0>2}", .{ch});
    try writer.writeByte('.');
}
var parse_mine_seed_err: StringSlice = undefined;
pub export fn ParseMineSeed(ptr: [*c]u8, len: usize) [*c]StringSlice {
    if (ptr == 0 or len == 0) {
        @panic("ptr or len is 0");
    }
    const error_msg = parse_mine_seed(ptr[0..len]);
    if (error_msg) |em| {
        wasm_jsalloc.slice_to_js(em) catch {
            allocator.free(em);
            allocation_error();
        };
        parse_mine_seed_err = .{ .len = em.len, .ptr = em.ptr };
        return &parse_mine_seed_err;
    } else return 0;
}
const Transition = struct {
    next_s: u32,
    begin: u8,
    end: u8,
};
const State = struct {
    transitions: []const Transition,
    accept: bool = false,
    pub const error_state: State = .{ .transitions = &.{} };
    pub const ERROR = 0;
    pub fn next(self: State, ch: u8) u32 {
        for (self.transitions) |*tr| {
            if (ch >= tr.begin and ch <= tr.end) return tr.next_s;
        } else return ERROR;
    }
};
///Regex format states: \d+x\d+, *([lmr]=([\da-fA-F]{2})+\. *)*
const ParseMineRegexStates = [_]State{
    .error_state,
    .{
        .transitions = &.{
            .{ .next_s = @intFromEnum(BoardInfoState.width_begin), .begin = '0', .end = '9' },
        },
    },
    .{
        .transitions = &.{
            .{ .next_s = @intFromEnum(BoardInfoState.width_begin), .begin = '0', .end = '9' },
            .{ .next_s = @intFromEnum(BoardInfoState.width_end), .begin = 'x', .end = 'x' },
        },
    },
    .{
        .transitions = &.{
            .{ .next_s = @intFromEnum(BoardInfoState.height_begin), .begin = '0', .end = '9' },
        },
    },
    .{
        .transitions = &.{
            .{ .next_s = @intFromEnum(BoardInfoState.height_begin), .begin = '0', .end = '9' },
            .{ .next_s = @intFromEnum(BoardInfoState.height_end), .begin = ',', .end = ',' },
        },
    },
    .{
        .transitions = &.{
            .{ .next_s = @intFromEnum(BoardInfoState.height_end), .begin = ' ', .end = ' ' },
            .{ .next_s = @intFromEnum(BoardInfoState.var_assign), .begin = 'l', .end = 'm' },
            .{ .next_s = @intFromEnum(BoardInfoState.var_assign), .begin = 'r', .end = 'r' },
        },
    },
    .{
        .transitions = &.{
            .{ .next_s = @intFromEnum(BoardInfoState.var_use), .begin = '=', .end = '=' },
        },
    },
    .{
        .transitions = &.{
            .{ .next_s = @intFromEnum(BoardInfoState.byte_begin), .begin = '0', .end = '9' },
            .{ .next_s = @intFromEnum(BoardInfoState.byte_begin), .begin = 'A', .end = 'F' },
            .{ .next_s = @intFromEnum(BoardInfoState.byte_begin), .begin = 'a', .end = 'f' },
        },
    },
    .{
        .transitions = &.{
            .{ .next_s = @intFromEnum(BoardInfoState.byte_end), .begin = '0', .end = '9' },
            .{ .next_s = @intFromEnum(BoardInfoState.byte_end), .begin = 'A', .end = 'F' },
            .{ .next_s = @intFromEnum(BoardInfoState.byte_end), .begin = 'a', .end = 'f' },
        },
    },
    .{
        .transitions = &.{
            .{ .next_s = @intFromEnum(BoardInfoState.byte_begin), .begin = '0', .end = '9' },
            .{ .next_s = @intFromEnum(BoardInfoState.byte_begin), .begin = 'A', .end = 'F' },
            .{ .next_s = @intFromEnum(BoardInfoState.byte_begin), .begin = 'a', .end = 'f' },
            .{ .next_s = @intFromEnum(BoardInfoState.complete), .begin = '.', .end = '.' },
        },
    },
    .{
        .accept = true,
        .transitions = &.{
            .{ .next_s = @intFromEnum(BoardInfoState.complete), .begin = ' ', .end = ' ' },
            .{ .next_s = @intFromEnum(BoardInfoState.var_assign), .begin = 'l', .end = 'm' },
            .{ .next_s = @intFromEnum(BoardInfoState.var_assign), .begin = 'r', .end = 'r' },
        },
    },
};
const BoardInfoState = enum(u32) {
    @"error" = State.ERROR,
    width_begin = 2,
    width_end = 3,
    height_begin = 4,
    height_end = 5,
    var_assign = 6,
    var_use = 7,
    byte_begin = 8,
    byte_end = 9,
    complete = 10,
    _,
};
var parsed_width: u32 = 0;
var parsed_height: u32 = 0;
var parsed_num_mines: u32 = 0;
pub export fn ParsedWidth() u32 {
    return parsed_width;
}
pub export fn ParsedHeight() u32 {
    return parsed_height;
}
pub export fn ParsedNumMines() u32 {
    return parsed_num_mines;
}
fn parse_mine_seed(seed_str: []const u8) ?[]u8 {
    clear_board();
    var state_now: u32 = 1;
    var var_to_use: u8 = undefined;
    var buf_to_use: *std.ArrayListUnmanaged(u8) = undefined;
    var str_buf: std.ArrayListUnmanaged(u8) = .empty;
    defer str_buf.deinit(allocator);
    for (seed_str, 0..) |ch, i| {
        state_now = ParseMineRegexStates[state_now].next(ch);
        switch (@as(BoardInfoState, @enumFromInt(state_now))) {
            BoardInfoState.@"error" => {
                return std.fmt.allocPrint(allocator, "Invalid character: '{c}' at index #{}", .{ ch, i }) catch allocation_error();
            },
            BoardInfoState.width_begin,
            BoardInfoState.height_begin,
            BoardInfoState.byte_begin,
            => str_buf.append(allocator, ch) catch allocation_error(),
            BoardInfoState.width_end => {
                parsed_width = std.fmt.parseInt(u32, str_buf.items, 10) catch allocation_error();
                str_buf.clearRetainingCapacity();
            },
            BoardInfoState.height_end => {
                if (ch == ',') {
                    parsed_height = std.fmt.parseInt(u32, str_buf.items, 10) catch allocation_error();
                    str_buf.clearRetainingCapacity();
                }
            },
            BoardInfoState.var_assign => {
                var_to_use = ch;
                buf_to_use = switch (ch) {
                    'l' => &left_click_board,
                    'm' => &mine_board,
                    'r' => &right_click_board,
                    else => unreachable,
                };
            },
            BoardInfoState.var_use => {},
            BoardInfoState.byte_end => {
                str_buf.append(allocator, ch) catch allocation_error();
                const byte = std.fmt.parseInt(u8, str_buf.items, 16) catch allocation_error();
                buf_to_use.append(allocator, byte) catch allocation_error();
                str_buf.clearRetainingCapacity();
            },
            BoardInfoState.complete => {
                if (ch == '.') {
                    const expected_size: u32 = ((parsed_width * parsed_height) + 7) / 8;
                    switch (var_to_use) {
                        'l', 'r' => |vstr| if (buf_to_use.items.len != expected_size)
                            return std.fmt.allocPrint(allocator, "Length of {} string must be the size of ceil((width * height) / 8) * 2, or {}", .{ vstr, expected_size * 2 }) catch allocation_error(),
                        'm' => {
                            if (mine_board.items.len != expected_size)
                                return std.fmt.allocPrint(allocator, "Length of m string must be the size of ceil((width * height) / 8) * 2, or {}", .{expected_size * 2}) catch allocation_error();
                            var board_mines: usize = 0;
                            const lower_bits_mask: u8 = nth_lower_bits_mask(@truncate((parsed_width * parsed_height) % 8));
                            for (0..mine_board.items.len - 1) |j| {
                                const mch = mine_board.items[j];
                                board_mines += @popCount(mch);
                            }
                            const last_byte = mine_board.getLast();
                            board_mines += @popCount(last_byte & lower_bits_mask);
                            parsed_num_mines = board_mines;
                        },
                        else => unreachable,
                    }
                }
            },
            _ => {},
        }
    }
    if (!ParseMineRegexStates[state_now].accept)
        return allocator.dupe(u8, "Seed string must end with a '.'") catch allocation_error();
    return null;
}
fn nth_lower_bits_mask(n: u3) u8 {
    return (@as(u8, 1) << n) -% 1;
}
fn allocation_error() noreturn {
    @panic("Allocation error.");
}
export fn UploadCurrentBoard() bool {
    const root_cm: *CalculatedMap = &@import("root").cm;
    return cm.move(root_cm, allocator) catch allocation_error();
}
