const std = @import("std");
const root = @import("root");
const wasm_allocator = root.wasm_allocator;
const CalculatedMap = root.CalculatedMap;
const wasm_jsalloc = @import("wasm_jsalloc.zig");
const StringSlice = @import("shared.zig").StringSlice;
const big_number = @import("big_number.zig");
const SolutionBitsRange = @import("minesweeper.zig").SolutionBits.SolutionBitsRange;
const MineFrequencyConvolute = @import("minesweeper.zig").MinesweeperMatrix.MineFrequencyConvolve;
const PlayProbabilityStatus = @import("shared.zig").PlayProbabilityStatus;
const FStruct = @import("shared.zig").FStruct;
pub var error_slice: StringSlice = .empty;
pub fn add_error_slice(err_msg: []u8) void {
    wasm_jsalloc.slice_to_js(err_msg) catch {
        wasm_allocator.free(err_msg);
        allocation_error();
    };
    error_slice = .{ .len = err_msg.len, .ptr = err_msg.ptr };
}
var cm: CalculatedMap = .empty;
var prng: std.Random.Pcg = .init(0);
pub export fn InitRNGSeed(seed: u64) void {
    prng = .init(seed);
}
var mine_board: std.ArrayList(u8) = .{};
var mine_board_ext: StringSlice = undefined;
pub export fn GetMineBoard() [*c]StringSlice {
    mine_board_ext = .{ .ptr = mine_board.items.ptr, .len = mine_board.items.len };
    return &mine_board_ext;
}
var left_click_board: std.ArrayList(u8) = .{};
var lcb_ext: StringSlice = undefined;
pub export fn GetLeftClickBoard() [*c]StringSlice {
    lcb_ext = .{ .ptr = left_click_board.items.ptr, .len = left_click_board.items.len };
    return &lcb_ext;
}
var right_click_board: std.ArrayList(u8) = .{};
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
var mine_seed: std.ArrayList(u8) = .{};
var mine_seed_ext: StringSlice = undefined;
pub export fn GetMineSeed() [*c]StringSlice {
    mine_seed_ext = .{ .ptr = mine_seed.items.ptr, .len = mine_seed.items.len };
    return &mine_seed_ext;
}
///Length is (width * height + 7) / 8 for javascript
pub export fn MinesweeperInitEmpty(num_mines: u32, width: u32, height: u32, safe_click: u32) [*c]StringSlice {
    const wtimesh = width * height;
    if (wtimesh == 0) {
        const err_msg = std.fmt.allocPrint(wasm_allocator, "Rows and Columns cannot be 0.", .{}) catch allocation_error();
        add_error_slice(err_msg);
        return &error_slice;
    }
    if (num_mines > width * height) {
        const err_msg = std.fmt.allocPrint(wasm_allocator, "Mine Count ({}) cannot exceed the number of Columns * Rows = {}", .{
            num_mines,
            width * height,
        }) catch allocation_error();
        add_error_slice(err_msg);
        return &error_slice;
    }
    clear_board();
    if (wtimesh != num_mines) {
        mine_board.appendNTimes(wasm_allocator, 0, (wtimesh + 7) / 8) catch allocation_error();
        var random_list = mine_tiles_random(wasm_allocator, prng.random(), .{ .mineboard = safe_click }, num_mines, width, height) catch allocation_error();
        defer random_list.deinit(wasm_allocator);
        for (random_list.items) |bb|
            mine_board.items[bb.byte] |= bb.bit;
    } else {
        mine_board.appendNTimes(wasm_allocator, std.math.maxInt(u8), (wtimesh + 7) / 8) catch allocation_error();
    }
    write_mine_seed(width, height) catch allocation_error();
    return 0;
}
fn write_mine_seed(width: u32, height: u32) !void {
    mine_seed.clearRetainingCapacity();
    const writer = mine_seed.writer(wasm_allocator);
    try writer.print("{}x{}, ", .{ width, height });
    try writer.writeAll("m=");
    for (mine_board.items) |ch| try writer.print("{x:0>2}", .{ch});
    try writer.writeByte('.');
    if (left_click_board.items.len != 0) {
        try writer.writeAll(" l=");
        for (left_click_board.items) |ch| try writer.print("{x:0>2}", .{ch});
        try writer.writeByte('.');
    }
    if (right_click_board.items.len != 0) {
        try writer.writeAll(" r=");
        for (right_click_board.items) |ch| try writer.print("{x:0>2}", .{ch});
        try writer.writeByte('.');
    }
}
pub export fn ParseMineSeed(ptr: [*c]u8, len: usize) [*c]StringSlice {
    if (ptr == 0 or len == 0) {
        @panic("ptr or len is 0");
    }
    const error_msg = parse_mine_seed(ptr[0..len]);
    if (error_msg) |em| {
        add_error_slice(em);
        return &error_slice;
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
    var buf_to_use: *std.ArrayList(u8) = undefined;
    var str_buf: std.ArrayList(u8) = .empty;
    defer str_buf.deinit(wasm_allocator);
    for (seed_str, 0..) |ch, i| {
        state_now = ParseMineRegexStates[state_now].next(ch);
        switch (@as(BoardInfoState, @enumFromInt(state_now))) {
            BoardInfoState.@"error" => {
                return std.fmt.allocPrint(wasm_allocator, "Invalid character: '{c}' at index #{}", .{ ch, i }) catch allocation_error();
            },
            BoardInfoState.width_begin,
            BoardInfoState.height_begin,
            BoardInfoState.byte_begin,
            => str_buf.append(wasm_allocator, ch) catch allocation_error(),
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
                str_buf.append(wasm_allocator, ch) catch allocation_error();
                const byte = std.fmt.parseInt(u8, str_buf.items, 16) catch allocation_error();
                buf_to_use.append(wasm_allocator, byte) catch allocation_error();
                str_buf.clearRetainingCapacity();
            },
            BoardInfoState.complete => {
                if (ch == '.') {
                    const expected_size: u32 = ((parsed_width * parsed_height) + 7) / 8;
                    switch (var_to_use) {
                        'l', 'r' => |vstr| if (buf_to_use.items.len != expected_size)
                            return std.fmt.allocPrint(wasm_allocator, "Length of {} string must be the size of ceil((width * height) / 8) * 2, or {}", .{ vstr, expected_size * 2 }) catch allocation_error(),
                        'm' => {
                            if (mine_board.items.len != expected_size)
                                return std.fmt.allocPrint(wasm_allocator, "Length of m string must be the size of ceil((width * height) / 8) * 2, or {}", .{expected_size * 2}) catch allocation_error();
                            var board_mines: usize = 0;
                            const lower_bits_mask: u8 = nth_lower_bits_mask(@truncate((parsed_width * parsed_height) % 8));
                            for (0..mine_board.items.len - 1) |j| {
                                const mch = mine_board.items[j];
                                board_mines += @popCount(mch);
                            }
                            const last_byte = mine_board.getLast();
                            board_mines += if (lower_bits_mask != 0) @popCount(last_byte & lower_bits_mask) else @popCount(last_byte);
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
        return wasm_allocator.dupe(u8, "Seed string must end with a '.'") catch allocation_error();
    return null;
}
fn nth_lower_bits_mask(n: u3) u8 {
    return (@as(u8, 1) << n) -% 1;
}
export fn UploadCurrentBoard() bool {
    const root_cm: *CalculatedMap = &root.cm;
    return cm.move(root_cm, wasm_allocator) catch allocation_error();
}
pub const BoardData = struct {
    include_mine_flags: bool,
    adj_mine_count: isize,
    all_mines_count: isize,
    non_adjacent_tiles: isize = 0,
    least_solution_mines: isize = 0,
    most_solution_mines: isize = 0,
    pub fn init(global_mine_count: isize, include_mine_flags: bool) BoardData {
        return .{
            .include_mine_flags = include_mine_flags,
            .all_mines_count = global_mine_count,
            .adj_mine_count = global_mine_count,
        };
    }
};
///The error messages are similar to global calculation in index.js
pub fn get_board_data(cm_p: *CalculatedMap, global_mine_count: isize, include_mine_flags: bool) ?BoardData {
    var bd: BoardData = .init(global_mine_count, include_mine_flags);
    var total_flag_mines: isize = 0;
    for (cm_p.map_parser.?.map.items) |ms_type| {
        if (ms_type == .unknown) {
            bd.non_adjacent_tiles += 1;
        } else if (include_mine_flags) {
            if (ms_type == .flag or ms_type == .mine) {
                bd.adj_mine_count -= 1;
                total_flag_mines += 1;
            }
        } else {
            if (ms_type == .flag or ms_type == .mine) {
                bd.all_mines_count += 1;
                total_flag_mines += 1;
            }
        }
    }
    if (bd.adj_mine_count < 0) {
        var err_msg: []u8 = undefined;
        if (include_mine_flags) {
            err_msg = std.fmt.allocPrint(wasm_allocator, "Error: The mines + flags placed ({}) exceeds the global mine count ({}).", .{
                total_flag_mines,
                global_mine_count,
            }) catch allocation_error();
        } else {
            err_msg = std.fmt.allocPrint(wasm_allocator, "Error: Global mine count is less than 0.", .{}) catch allocation_error();
        }
        add_error_slice(err_msg);
        return null;
    }
    for (cm_p.mm_subsystems) |*mm_sub| {
        bd.non_adjacent_tiles -= @bitCast(mm_sub.tm.idtol.items.len);
        for (mm_sub.sb.get_range_bits(0)) |*b| {
            bd.least_solution_mines += @popCount(b.*);
        }
        for (mm_sub.sb.get_range_bits(mm_sub.sb.data.items.len / mm_sub.sb.number_bytes - 1)) |*b| {
            bd.most_solution_mines += @popCount(b.*);
        }
    }
    if (bd.adj_mine_count < bd.least_solution_mines) {
        var err_msg: []u8 = undefined;
        if (include_mine_flags) {
            err_msg = std.fmt.allocPrint(wasm_allocator, "Error: Too little mines! The global mine count is {} - ({} mines + flags) = {}. All solutions require at least {} or more mines. Global mine count must be >= {}.", .{
                bd.all_mines_count,
                total_flag_mines,
                bd.adj_mine_count,
                bd.least_solution_mines,
                total_flag_mines + bd.least_solution_mines,
            }) catch allocation_error();
        } else {
            err_msg = std.fmt.allocPrint(wasm_allocator, "Error: Too little mines! The global mine count is {}. All solutions require at least {[1]} or more mines. Global mine count must be >= {[1]}.", .{
                bd.adj_mine_count,
                bd.least_solution_mines,
            }) catch allocation_error();
        }
        add_error_slice(err_msg);
        return null;
    }
    if (bd.adj_mine_count > bd.most_solution_mines + bd.non_adjacent_tiles) {
        var err_msg: []u8 = undefined;
        if (include_mine_flags) {
            err_msg = std.fmt.allocPrint(wasm_allocator, "Error: Too many mines! The global mine count is {} - ({} mines + flags) = {}. One solution has a maximum of {} mines and there are only {} non-adjacent tiles to fill, resulting in the sum of only {} mines. Global mine count must be <= {}.", .{
                bd.all_mines_count,
                total_flag_mines,
                bd.adj_mine_count,
                bd.most_solution_mines,
                bd.non_adjacent_tiles,
                bd.most_solution_mines + bd.non_adjacent_tiles,
                total_flag_mines + bd.most_solution_mines + bd.non_adjacent_tiles,
            }) catch allocation_error();
        } else {
            err_msg = std.fmt.allocPrint(wasm_allocator, "Error: Too many mines! The global mine count is {}. One solution has a maximum of {} mines and there are only {} non-adjacent tiles to fill, resulting in the sum of only {[3]} mines. Global mine count must be <= {[3]}.", .{
                bd.adj_mine_count,
                bd.most_solution_mines,
                bd.non_adjacent_tiles,
                bd.most_solution_mines + bd.non_adjacent_tiles,
            }) catch allocation_error();
        }
        add_error_slice(err_msg);
        return null;
    }
    return bd;
}
export fn HasUploaded() bool {
    return cm.is_probability_calculated();
}
export fn CheckCurrentBoard(global_mine_count: isize, include_mine_flags: bool) [*c]StringSlice {
    std.debug.assert(cm.is_probability_calculated());
    _ = get_board_data(&cm, global_mine_count, include_mine_flags) orelse return &error_slice;
    return 0;
}
fn allocation_error() noreturn {
    @panic("Allocation error.");
}
const ByteBit = struct {
    byte: usize,
    bit: u8,
    fn init_xy(x: usize, y: usize, width: usize) ByteBit {
        return .init_i(y * width + x);
    }
    fn init_i(i: usize) ByteBit {
        return .{ .byte = i / 8, .bit = @as(u8, 1) << @truncate(i & 0b111) };
    }
};
pub const MineTilesFilter = union(enum) {
    ///Represents the safe click tile (Don't add any mines here)
    mineboard: usize,
    all: void,
};
fn next_empty(filter_type: MineTilesFilter, tile_ptr: *usize, width: usize, height: usize) ?ByteBit {
    if (tile_ptr.* == width * height) return null;
    var bb: ByteBit = undefined;
    if (filter_type == .mineboard) {
        if (tile_ptr.* == filter_type.mineboard) {
            tile_ptr.* += 1;
            if (tile_ptr.* == width * height) return null;
        }
        bb = .init_i(tile_ptr.*);
    } else {
        bb = .init_i(tile_ptr.*);
        while (left_click_board.items[bb.byte] & bb.bit != 0 or right_click_board.items[bb.byte] & bb.bit != 0) {
            tile_ptr.* += 1;
            if (tile_ptr.* == width * height) return null;
            bb = .init_i(tile_ptr.*);
        }
    }
    return bb;
}
///Using reservoir sampling algorithm to uniformly add mines.
fn mine_tiles_random(
    allocator: std.mem.Allocator,
    random: std.Random,
    filter_type: MineTilesFilter,
    num_mines: usize,
    width: usize,
    height: usize,
) !std.ArrayList(ByteBit) {
    var tile_ptr: usize = 0;
    var random_list: std.ArrayList(ByteBit) = .empty;
    errdefer random_list.deinit(allocator);
    try random_list.ensureTotalCapacityPrecise(allocator, num_mines);
    random_list.items.len = num_mines;
    for (0..num_mines) |i| { //Fill list with empty tiles.
        random_list.items[i] = next_empty(filter_type, &tile_ptr, width, height).?;
        tile_ptr += 1;
    }
    var count: usize = num_mines;
    while (next_empty(filter_type, &tile_ptr, width, height)) |bb| {
        const i = random.intRangeAtMost(usize, 0, count);
        if (i < num_mines) random_list.items[i] = bb;
        tile_ptr += 1;
        count += 1;
    }
    return random_list;
}
//Index of conv_ctr is SubSystem index, and .c is MineFrequency index (.m is maximum per SubSystem).
pub const SSMF = struct {
    c: usize = 0,
    m: usize,
};
pub fn mfcs_create(cm_p: *CalculatedMap, bd: BoardData, mines_left: isize, as_running_total: bool) !std.ArrayList(MineFrequencyConvolute) {
    var conv_ctr: std.ArrayList(SSMF) = .empty;
    defer conv_ctr.deinit(wasm_allocator);
    const ss_len = cm_p.mm_subsystems.len;
    for (0..ss_len) |ss_i| {
        const calc = &cm_p.calculate_array.ptr[ss_i];
        const mf_len = calc.pl.mf_len;
        try conv_ctr.append(wasm_allocator, .{ .m = mf_len });
    }
    var mfcs: std.ArrayList(MineFrequencyConvolute) = .empty;
    errdefer {
        for (mfcs.items) |*m|
            m.deinit(wasm_allocator);
        mfcs.deinit(wasm_allocator);
    }
    //Get the formula for "Math Explanation > Convolution to Calculate Mine Count and Frequencies of the Whole Board"
    //The weight for each individual convoluted .m and .f is considered.
    while (true) : ({
        //Increment counters until 0 is reached for all
        for (0..conv_ctr.items.len) |ctr_i| {
            conv_ctr.items[ctr_i].c += 1;
            if (conv_ctr.items[ctr_i].c == conv_ctr.items[ctr_i].m) {
                conv_ctr.items[ctr_i].c = 0;
                continue;
            }
            break;
        } else break;
    }) {
        var mfc: MineFrequencyConvolute = try .init(wasm_allocator);
        errdefer mfc.deinit(wasm_allocator);
        for (0..conv_ctr.items.len) |ss_i| {
            const mf_i = conv_ctr.items[ss_i].c;
            const mf = cm_p.calculate_array.slice()[ss_i].pl.mf_slice()[mf_i];
            try mfc.convolve(wasm_allocator, mf, mf_i);
        }
        //Only use valid mine count solutions within ranges.
        if (mines_left < mfc.m) { //Exclude too little .m
            mfc.deinit(wasm_allocator);
            continue;
        }
        if (mines_left - bd.non_adjacent_tiles > mfc.m) { //Exclude too many leftover .m mines
            mfc.deinit(wasm_allocator);
            continue;
        }
        const g_min_m: u32 = @truncate(@as(usize, @bitCast(bd.adj_mine_count)) - mfc.m);
        var bui_comb = try big_number.bui_comb(
            wasm_allocator,
            @truncate(@as(usize, @bitCast(bd.non_adjacent_tiles))),
            g_min_m,
        ); //Multiply convoluted f with comb(unknown_non-adjacent_tiles, mine_count - mfc.m)
        defer bui_comb.deinit(wasm_allocator);
        try mfc.f.multiply(wasm_allocator, &bui_comb);
        try mfcs.append(wasm_allocator, mfc);
    }
    if (as_running_total) {
        for (0..mfcs.items.len) |j| { //Make as running total to get a big number unsigned integer [0,running total).
            const rev_i = mfcs.items.len - 1 - j;
            const last_f = &mfcs.items[rev_i].f;
            for (0..rev_i) |k|
                try last_f.add(wasm_allocator, &mfcs.items[k].f);
        }
    }
    return mfcs;
}
fn create_preset_board(bd: BoardData) !void {
    const board_size: u32 = (@as(u32, @truncate(cm.map_parser.?.map.items.len)) + 7) / 8;
    try mine_board.appendNTimes(wasm_allocator, 0, board_size);
    try left_click_board.appendNTimes(wasm_allocator, 0, board_size);
    try right_click_board.appendNTimes(wasm_allocator, 0, board_size);
    for (cm.map_parser.?.map.items, 0..) |ms_type, i| {
        const bb: ByteBit = .init_i(i);
        if (ms_type == .mine) {
            mine_board.items[bb.byte] |= bb.bit;
        }
        if (ms_type == .flag) {
            right_click_board.items[bb.byte] |= bb.bit;
            mine_board.items[bb.byte] |= bb.bit; //Mine in flag
        }
        if (ms_type.is_number() or ms_type == .donotcare)
            left_click_board.items[bb.byte] |= bb.bit;
    }
    var mines_left = bd.adj_mine_count;
    var i_array: std.ArrayList(usize) = .empty;
    defer i_array.deinit(wasm_allocator);
    var mfcs = try mfcs_create(&cm, bd, mines_left, true);
    defer {
        for (mfcs.items) |*m|
            m.deinit(wasm_allocator);
        mfcs.deinit(wasm_allocator);
    }
    var mfc_f_random: big_number.BigUInt = try .init_random(wasm_allocator, prng.random(), &mfcs.items[mfcs.items.len - 1].f);
    defer mfc_f_random.deinit(wasm_allocator);
    var chosen_mfc: usize = 0;
    while (mfc_f_random.order(&mfcs.items[chosen_mfc].f) != .lt) : (chosen_mfc += 1) {}
    //std.log.warn("{} {any}\n", .{ chosen_mfc, mfc_f_random.bytes });
    const chosen_mds = mfcs.items[chosen_mfc].mds.items;
    mines_left -= @bitCast(mfcs.items[chosen_mfc].m);
    for (0.., chosen_mds) |ss_i, mf_i| {
        const sbr = cm.mm_subsystems[ss_i].sb.metadata.items[mf_i];
        const random_i = prng.random().intRangeLessThan(usize, sbr.begin, sbr.end);
        //std.log.err("{} {} {any} {}\n", .{ ss_i, mf_i, sbr, random_i });
        try i_array.append(wasm_allocator, random_i);
    }
    for (0..cm.mm_subsystems.len) |i| {
        const idtol = &cm.mm_subsystems[i].tm.idtol;
        for (0..idtol.items.len) |j| {
            const l_bb: ByteBit = .init_xy(idtol.items[j].x, idtol.items[j].y, cm.map_parser.?.width);
            left_click_board.items[l_bb.byte] |= l_bb.bit; //left_click_board idtol used as mask to add remaining leftover mines.
        }
    }
    {
        var random_list = try mine_tiles_random(wasm_allocator, prng.random(), .all, @bitCast(mines_left), cm.map_parser.?.width, cm.map_parser.?.height);
        defer random_list.deinit(wasm_allocator);
        for (random_list.items) |bb|
            mine_board.items[bb.byte] |= bb.bit;
    }
    for (i_array.items, 0..) |ri, i| {
        const solution_bits = cm.mm_subsystems[i].sb.get_range_bits(ri);
        const idtol = &cm.mm_subsystems[i].tm.idtol;
        for (0..idtol.items.len) |j| {
            const sb_byte: usize = j / 32;
            const sb_bit: u32 = @as(u32, 1) << @truncate(j & 0b11111);
            const l_bb: ByteBit = .init_xy(idtol.items[j].x, idtol.items[j].y, cm.map_parser.?.width);
            if (solution_bits[sb_byte] & sb_bit != 0) { //Add solution mines to mine_board
                mine_board.items[l_bb.byte] |= l_bb.bit;
            }
            left_click_board.items[l_bb.byte] ^= l_bb.bit; //Clear left_click_board idtol mask
        }
    }
}
fn minesweeper_init_board(global_mine_count: isize, include_mine_flags: bool) ![*c]StringSlice {
    std.debug.assert(cm.is_probability_calculated());
    clear_board();
    const bd = get_board_data(&cm, global_mine_count, include_mine_flags) orelse return &error_slice;
    try create_preset_board(bd);
    write_mine_seed(@truncate(cm.map_parser.?.width), @truncate(cm.map_parser.?.height)) catch allocation_error();
    parsed_width = @truncate(cm.map_parser.?.width);
    parsed_height = @truncate(cm.map_parser.?.height);
    parsed_num_mines = @truncate(@as(usize, @bitCast(bd.all_mines_count)));
    return 0;
}
pub export fn MinesweeperInitBoard(global_mine_count: isize, include_mine_flags: bool) [*c]StringSlice {
    return minesweeper_init_board(global_mine_count, include_mine_flags) catch allocation_error();
}
fn to_xy(i: usize, width: usize) [2]usize {
    return .{ i % width, i / width };
}
fn get_adj_tiles_bb(adj_tiles: []ByteBit, tile_i: usize, width: usize, height: usize) []ByteBit {
    const xy = to_xy(tile_i, width);
    var size_now: usize = 0;
    //Clockwise adjacency starting from top to top left.
    const not_topmost = xy[1] != 0;
    const not_rightmost = xy[0] != width - 1;
    const not_bottommost = xy[1] != height - 1;
    const not_leftmost = xy[0] != 0;
    if (not_topmost) {
        adj_tiles[size_now] = .init_i(xy[0] + (xy[1] - 1) * width);
        size_now += 1;
    }
    if (not_topmost and not_rightmost) {
        adj_tiles[size_now] = .init_i(xy[0] + 1 + (xy[1] - 1) * width);
        size_now += 1;
    }
    if (not_rightmost) {
        adj_tiles[size_now] = .init_i(xy[0] + 1 + xy[1] * width);
        size_now += 1;
    }
    if (not_rightmost and not_bottommost) {
        adj_tiles[size_now] = .init_i(xy[0] + 1 + (xy[1] + 1) * width);
        size_now += 1;
    }
    if (not_bottommost) {
        adj_tiles[size_now] = .init_i(xy[0] + (xy[1] + 1) * width);
        size_now += 1;
    }
    if (not_bottommost and not_leftmost) {
        adj_tiles[size_now] = .init_i(xy[0] - 1 + (xy[1] + 1) * width);
        size_now += 1;
    }
    if (not_leftmost) {
        adj_tiles[size_now] = .init_i(xy[0] - 1 + xy[1] * width);
        size_now += 1;
    }
    if (not_leftmost and not_topmost) {
        adj_tiles[size_now] = .init_i(xy[0] - 1 + (xy[1] - 1) * width);
        size_now += 1;
    }
    return adj_tiles[0..size_now];
}
export var PPStatus: PlayProbabilityStatus = .idle;
pub export fn CancelProbability() void { //If .running, wait until it becomes .idle again
    if (@atomicLoad(PlayProbabilityStatus, &PPStatus, .acquire) == .idle) return;
    @atomicStore(PlayProbabilityStatus, &PPStatus, .cancel, .release);
    while (@atomicLoad(PlayProbabilityStatus, &PPStatus, .acquire) == .cancel) {}
}
var f_struct: FStruct = .{ .f = [1]usize{0} ** 10, .t = 0 };
extern fn ReturnProbabilityStats([*c]FStruct, usize) void;
pub export fn ProbabilityClickTile(global_mine_count: isize, include_mine_flags: bool, tile_i: usize) void {
    std.debug.assert(cm.is_probability_calculated());
    clear_board();
    const bd_o = get_board_data(&cm, global_mine_count, include_mine_flags);
    if (bd_o) |bd| {
        //Counts from 0 number tile (0), 1 number tile (1), 2 number tile (2), ... 8 number tile (8), and mine tile (9).
        var f_table: [10]usize = [1]usize{0} ** 10;
        var f_total: usize = 1;
        f_struct.f = f_table;
        f_struct.t = f_total;
        ReturnProbabilityStats(&f_struct, tile_i); //Clear current board.
        f_total = 0;
        var adj_bb: [8]ByteBit = undefined;
        const adj_slice = get_adj_tiles_bb(&adj_bb, tile_i, cm.map_parser.?.width, cm.map_parser.?.height);
        const this_bb: ByteBit = .init_i(tile_i);
        PPStatus = .running;
        while (@atomicLoad(PlayProbabilityStatus, &PPStatus, .acquire) == .running) {
            clear_board();
            create_preset_board(bd) catch allocation_error();
            if (mine_board.items[this_bb.byte] & this_bb.bit != 0) {
                f_table[9] += 1;
            } else {
                var num_mines: usize = 0;
                for (adj_slice) |a_bb| {
                    if (mine_board.items[a_bb.byte] & a_bb.bit != 0) num_mines += 1;
                }
                f_table[num_mines] += 1;
            }
            f_total += 1;
            if (@atomicLoad(bool, &root.CalculateStatus, .acquire)) {
                @atomicStore(bool, &root.CalculateStatus, false, .release);
                f_struct.f = f_table;
                f_struct.t = f_total;
                ReturnProbabilityStats(&f_struct, tile_i);
            }
        }
    } else wasm_jsalloc.WasmFree(error_slice.ptr);
    @atomicStore(PlayProbabilityStatus, &PPStatus, .idle, .release);
}
