const std = @import("std");
const wasm_print = @import("wasm_print.zig");
const logger = @import("logger.zig");
const minesweeper = @import("minesweeper.zig");
const shared = @import("shared.zig");
const rng = @import("rng.zig");
const StringSlice = @import("shared.zig").StringSlice;
const get_board_data = @import("rng.zig").get_board_data;
const big_number = @import("big_number.zig");
pub const wasm_allocator = std.heap.wasm_allocator;
pub const std_options: std.Options = .{
    .logFn = logger.std_options_impl.logFn,
};
pub const panic = std.debug.FullPanic(wasm_print.panic);
var t1_stack: [65536]u8 align(16) = undefined;
var t2_stack: [65536]u8 align(16) = undefined;
export fn T1StackTop() [*c]u8 {
    return &t1_stack[t1_stack.len - 16];
}
export fn T2StackTop() [*c]u8 {
    return &t2_stack[t2_stack.len - 16];
}
comptime {
    _ = @import("wasm_jsalloc.zig");
    _ = @import("rng.zig");
}
pub const CalculatedMap = struct {
    map_parser: ?minesweeper.MapParser,
    calculate_array: shared.CalculateArray,
    mm_whole: minesweeper.MinesweeperMatrix,
    mm_subsystems: []minesweeper.MinesweeperMatrix,
    last_calculate_str: ?[]u8,
    edited: bool,
    pub const empty: CalculatedMap = .{
        .map_parser = null,
        .calculate_array = .init_error(.unknown),
        .mm_whole = .empty,
        .mm_subsystems = &.{},
        .last_calculate_str = null,
        .edited = false,
    };
    pub fn is_probability_calculated(self: CalculatedMap) bool {
        if (self.edited) return false;
        if (self.calculate_array.status != .ok) return false;
        for (self.calculate_array.ptr[0..self.calculate_array.len]) |*c|
            if (c.status != .ok) return false;
        return true;
    }
    /// Move all data but keep map parser clone.
    pub fn move(self: *CalculatedMap, other: *CalculatedMap, allocator: std.mem.Allocator) !bool {
        if (other.is_probability_calculated()) {
            const mp_clone = try other.*.map_parser.?.clone(allocator);
            self.deinit_all(allocator);
            self.* = other.*;
            other.* = .empty;
            other.map_parser = mp_clone;
            other.edited = false;
            return true;
        }
        return false;
    }
    pub fn deinit_mp(self: *CalculatedMap, allocator: std.mem.Allocator) void {
        if (self.map_parser) |*mp| mp.deinit(allocator);
        self.map_parser = null;
    }
    pub fn deinit_array_and_matrices(self: *CalculatedMap, allocator: std.mem.Allocator) void {
        self.calculate_array.deinit(allocator);
        for (self.mm_subsystems) |*mm| mm.deinit(allocator);
        allocator.free(self.mm_subsystems);
        self.mm_subsystems = &.{};
        self.mm_whole.deinit(allocator);
        self.mm_whole = .empty;
    }
    pub fn deinit_last_calculate_str(self: *CalculatedMap, allocator: std.mem.Allocator) void {
        if (self.last_calculate_str) |lcstr| allocator.free(lcstr);
        self.last_calculate_str = null;
    }
    pub fn deinit_all(self: *CalculatedMap, allocator: std.mem.Allocator) void {
        self.deinit_mp(allocator);
        self.deinit_array_and_matrices(allocator);
        self.deinit_last_calculate_str(allocator);
    }
};
pub var cm: CalculatedMap = .empty;
export fn CreateGrid(width: usize, height: usize) void {
    cm.deinit_mp(wasm_allocator);
    const mp_status = minesweeper.MapParser.init(wasm_allocator, width, height);
    if (mp_status == .ok) {
        cm.map_parser = mp_status.ok;
        wasm_print.FlushPrint(false);
    } else {
        std.log.err("Allocator error at CreateGrid\n", .{});
        wasm_print.FlushPrint(false);
    }
}
/// Return -1 if x/y is out of range
export fn QueryTile(x: usize, y: usize) usize {
    if (cm.map_parser) |mp| {
        if (mp.query_tile(x, y)) |t| {
            return @intFromEnum(t);
        } else {
            std.log.err("QueryTile out of range x:{}, y:{}. width x height is {} by {}.\n", .{ x, y, mp.width, mp.height });
            wasm_print.FlushPrint(false);
            return std.math.maxInt(usize);
        }
    } else {
        std.log.err("MapParser was not created yet.\n", .{});
        wasm_print.FlushPrint(false);
        return std.math.maxInt(usize);
    }
}
/// Returns true if error.
export fn SetTile(x: usize, y: usize, tile: usize) bool {
    cm.edited = true;
    if (cm.map_parser) |*mp| {
        mp.set_tile(x, y, tile) catch |e| {
            switch (e) {
                error.LocationOutOfRange => {
                    std.log.err("SetTile out of range x:{}, y:{}. width x height is {} by {}.\n", .{ x, y, mp.width, mp.height });
                    wasm_print.FlushPrint(false);
                    return true;
                },
                error.TileOutOfRange => {
                    std.log.err("Tile enumeration is out of range.\n", .{});
                    wasm_print.FlushPrint(false);
                    return true;
                },
            }
        };
        return false;
    } else {
        std.log.err("MapParser was not created yet.\n", .{});
        wasm_print.FlushPrint(false);
        return true;
    }
}
fn stringify_matrix(
    allocator: std.mem.Allocator,
    mm: *const minesweeper.MinesweeperMatrix,
    show_ids: bool,
) !std.ArrayList(u8) {
    var results: std.ArrayList(u8) = .empty;
    errdefer results.deinit(allocator);
    if (mm.lcs.items.len == 0) try results.writer(allocator).writeAll("\\(empty\\)<br><br>");
    for (mm.lcs.items) |lc| {
        var next: ?*const minesweeper.Term = lc.head;
        try results.writer(allocator).writeAll("\\(");
        if (next) |n| {
            if (n.id == null) {
                try results.writer(allocator).print("0={}\\)<br>", .{n.v});
                continue;
            } else {
                if (n.v != 1) try results.writer(allocator).print("{}", .{n.v});
                try results.writer(allocator).print("x_{{{any}}}", .{n.id});
            }
            next = n.next;
        }
        while (next) |n| {
            if (n.id == null) {
                try results.writer(allocator).print("={}\\)<br>", .{n.v});
                break;
            } else {
                try results.append(allocator, if (n.v > 0) '+' else '-');
                if (@abs(n.v) != 1) {
                    try results.writer(allocator).print("{}", .{@abs(n.v)});
                }
                try results.writer(allocator).print("x_{{{any}}}", .{n.id});
            }
            next = n.next;
        }
    }
    if (show_ids) {
        if (mm.tm.idtol.items.len != 0)
            try results.writer(allocator).writeAll("Where \\(");
        for (mm.tm.idtol.items, 0..) |loc, id| {
            try results.writer(allocator).print("x_{{{any}}}=\\langle{},{}\\rangle,\\,", .{ id, loc.x, loc.y });
        }
        if (mm.tm.idtol.items.len != 0) {
            try results.writer(allocator).writeAll("\\)<br>");
            try results.writer(allocator).writeAll("<br>");
        }
    }
    return results;
}
export fn CalculateProbability() [*c]shared.CalculateArray {
    cm.edited = false;
    defer @atomicStore(bool, &CancelCalculation, false, .release);
    var cmp_calculate_str: []u8 = undefined;
    if (cm.map_parser) |mp| {
        cmp_calculate_str = mp.as_str(wasm_allocator) catch return 0;
    } else return 0;
    defer wasm_allocator.free(cmp_calculate_str);
    if (cm.calculate_array.status == .ok) {
        for (cm.calculate_array.ptr[0..cm.calculate_array.len]) |*calc| {
            if (calc.status == .cancelled)
                break; //If calculation was cancelled previously, reenable recalculating again ('else if' block doesn't run).
        } else if (cm.last_calculate_str) |lcstr| {
            if (std.mem.eql(u8, lcstr, cmp_calculate_str)) {
                cm.calculate_array.recalculated = false;
                return &cm.calculate_array; //If the same board, just return the same pointer without recalculation.
            }
        }
    }
    cm.deinit_array_and_matrices(wasm_allocator);
    ClearResults();
    if (cm.map_parser) |mp| error_happened: {
        cm.mm_whole = mp.to_minesweeper_matrix(wasm_allocator) catch |e| {
            cm.calculate_array = switch (e) {
                error.OutOfMemory => .init_error(.alloc_error),
                else => |e2| v: {
                    std.log.err("{any}\n", .{e2});
                    break :v .init_error(.unknown);
                },
            };
            break :error_happened;
        };
        {
            const sm = "Solving minesweeper matrix:<br>";
            AppendResults(sm, sm.len);
            var mm_whole_str = stringify_matrix(wasm_allocator, &cm.mm_whole, true) catch {
                cm.calculate_array = .init_error(.alloc_error);
                break :error_happened;
            };
            defer mm_whole_str.deinit(wasm_allocator);
            AppendResults(mm_whole_str.items.ptr, mm_whole_str.items.len);
            wasm_print.FlushPrint(false);
        }
        cm.mm_subsystems = cm.mm_whole.separate_subsystems(wasm_allocator) catch |e| {
            cm.calculate_array = switch (e) {
                error.OutOfMemory => .init_error(.alloc_error),
                error.NoSolutions => .init_error(.no_solutions),
                else => |e2| v: {
                    std.log.err("{any}\n", .{e2});
                    break :v .init_error(.unknown);
                },
            };
            break :error_happened;
        };
        if (cm.mm_subsystems.len > 1) {
            const sm = "This matrix can be partitioned into the following subsystems:<br><br>";
            AppendResults(sm, sm.len);
            for (cm.mm_subsystems, 0..) |sub_mm, ss_i| {
                var alloc_sm: std.ArrayList(u8) = .empty;
                defer alloc_sm.deinit(wasm_allocator);
                alloc_sm.writer(wasm_allocator).print("Subsystem #{}<br>", .{ss_i}) catch {
                    cm.calculate_array = .init_error(.alloc_error);
                    break :error_happened;
                };
                AppendResults(alloc_sm.items.ptr, alloc_sm.items.len);
                var sub_mm_str = stringify_matrix(wasm_allocator, &sub_mm, true) catch {
                    cm.calculate_array = .init_error(.alloc_error);
                    break :error_happened;
                };
                defer sub_mm_str.deinit(wasm_allocator);
                AppendResults(sub_mm_str.items.ptr, sub_mm_str.items.len);
            }
        }
        const pl_list = wasm_allocator.alloc(shared.Calculate, cm.mm_subsystems.len) catch {
            cm.calculate_array = .init_error(.alloc_error);
            break :error_happened;
        };
        for (pl_list) |*pl|
            pl.* = .init_error(.alloc_error);
        cm.calculate_array = .{
            .status = .ok,
            .recalculated = true,
            .ptr = pl_list.ptr,
            .len = pl_list.len,
        };
        if (pl_list.len != 0) {
            const sm = "Solving the following system(s) using RREF and brute forcing 0 or 1 for each \\(x_n\\) free variable<br><br>";
            AppendResults(sm, sm.len);
            SetSubsystemNumber(pl_list.len);
        }
        for (0..cm.mm_subsystems.len) |i| {
            var alloc_sm: std.ArrayList(u8) = .empty;
            defer alloc_sm.deinit(wasm_allocator);
            alloc_sm.writer(wasm_allocator).print("RREF Subsystem #{}<br>", .{i}) catch {
                cm.calculate_array = .init_error(.alloc_error);
                break :error_happened;
            };
            AppendResults(alloc_sm.items.ptr, alloc_sm.items.len);
            const this_mm = &cm.mm_subsystems[i];
            const pl = this_mm.solve(wasm_allocator, i) catch |e| {
                pl_list[i] = switch (e) {
                    error.OverFlag => .init_error(.overflag),
                    error.NoSolutionsFound => .init_error(.no_solutions_subsystem),
                    error.OutOfMemory => .init_error(.alloc_error),
                    error.CalculationCancelled => .init_error(.cancelled),
                };
                pl_list[i].tm = this_mm.tm.get_id_to_location_extern();
                const sm = "No valid solutions were found for this subsystem.<br><br>";
                AppendResults(sm, sm.len);
                continue;
            };
            var this_mm_str: std.ArrayList(u8) = stringify_matrix(wasm_allocator, this_mm, false) catch .empty;
            defer this_mm_str.deinit(wasm_allocator);
            if (pl.total != 0) {
                pl_list[i] = .{
                    .pl = pl,
                    .status = .ok,
                    .tm = this_mm.tm.get_id_to_location_extern(),
                    .sb = this_mm.sb.get_solution_bits_extern(),
                };
                this_mm_str.writer(wasm_allocator).print("<br>", .{}) catch {};
            } else {
                pl_list[i] = .init_error(.no_solutions_subsystem);
                pl_list[i].tm = this_mm.tm.get_id_to_location_extern();
                this_mm_str.writer(wasm_allocator).writeAll("No valid solutions were found for this subsystem.<br><br>") catch {};
            }
            AppendResults(this_mm_str.items.ptr, this_mm_str.items.len);
        }
    }
    wasm_print.FlushPrint(false);
    FinalizeResults();
    if (cm.calculate_array.status == .ok) { //Set null if not .ok for any status
        for (cm.calculate_array.ptr[0..cm.calculate_array.len]) |ca| {
            if (ca.status != .ok) {
                if (cm.last_calculate_str) |lcstr| wasm_allocator.free(lcstr);
                cm.last_calculate_str = null;
            }
        } else {
            if (cm.last_calculate_str) |lcstr| wasm_allocator.free(lcstr);
            cm.last_calculate_str = wasm_allocator.dupe(u8, cmp_calculate_str) catch null;
        }
    } else {
        if (cm.last_calculate_str) |lcstr| wasm_allocator.free(lcstr);
        cm.last_calculate_str = null;
    }
    return &cm.calculate_array;
}
const SSID = struct {
    ss: usize,
    id: usize,
};
const LocationHM = std.HashMapUnmanaged(minesweeper.TileLocation, SSID, LocationHMCtx, 80);
const LocationHMCtx = struct {
    pub fn hash(_: @This(), a: minesweeper.TileLocation) u64 {
        //For wasm, usize is 32 bit.
        const h: [2]usize = .{ a.x, a.y };
        return @bitCast(h);
    }
    pub fn eql(_: @This(), a: minesweeper.TileLocation, b: minesweeper.TileLocation) bool {
        return a.x == b.x and a.y == b.y;
    }
};
/// Hypergeometric distribution. exclude_one is used whenever a current tile is not an adjacent tile (always safe)
/// in order to count region mines correctly.
fn hg_numerator(exclude_one: bool, bd: rng.BoardData, leftover_m: u32, r_m: u32, r: u32) !big_number.BigUInt {
    if (leftover_m >= r_m) {
        var res_bui = try big_number.bui_comb(wasm_allocator, r, r_m);
        errdefer res_bui.deinit(wasm_allocator);
        const total_non_adjacent: u32 = @truncate(@as(usize, @bitCast(bd.non_adjacent_tiles)));
        std.debug.assert(total_non_adjacent >= r);
        var rest_leftover_comb = try big_number.bui_comb(wasm_allocator, total_non_adjacent - r, leftover_m - r_m);
        defer rest_leftover_comb.deinit(wasm_allocator);
        if (exclude_one and r_m != 0) {
            var comb_mine_in_excluded = try big_number.bui_comb(wasm_allocator, r - 1, r_m - 1);
            defer comb_mine_in_excluded.deinit(wasm_allocator);
            const should_be_pos = try res_bui.sub(wasm_allocator, &comb_mine_in_excluded);
            std.debug.assert(should_be_pos);
        }
        try res_bui.multiply(wasm_allocator, &rest_leftover_comb);
        return res_bui;
    } else return .init(wasm_allocator, 0);
}
const TilesMetadata = struct {
    middle: minesweeper.TileLocation,
    tiles: [8]minesweeper.TileLocation,
    len: usize,
    fn init(x: usize, y: usize, width: usize, height: usize) TilesMetadata {
        const xgt0 = x > 0;
        const xltw = x < width - 1;
        const ygt0 = y > 0;
        const ylth = y < height - 1;
        var at: TilesMetadata = .{ .middle = .{ .x = x, .y = y }, .tiles = undefined, .len = 0 };
        if (ygt0) {
            at.tiles[at.len] = .{ .y = y - 1, .x = x };
            at.len += 1;
        }
        if (ygt0 and xltw) {
            at.tiles[at.len] = .{ .y = y - 1, .x = x + 1 };
            at.len += 1;
        }
        if (xltw) {
            at.tiles[at.len] = .{ .y = y, .x = x + 1 };
            at.len += 1;
        }
        if (ylth and xltw) {
            at.tiles[at.len] = .{ .y = y + 1, .x = x + 1 };
            at.len += 1;
        }
        if (ylth) {
            at.tiles[at.len] = .{ .y = y + 1, .x = x };
            at.len += 1;
        }
        if (ylth and xgt0) {
            at.tiles[at.len] = .{ .y = y + 1, .x = x - 1 };
            at.len += 1;
        }
        if (xgt0) {
            at.tiles[at.len] = .{ .y = y, .x = x - 1 };
            at.len += 1;
        }
        if (ygt0 and xgt0) {
            at.tiles[at.len] = .{ .y = y - 1, .x = x - 1 };
            at.len += 1;
        }
        return at;
    }
    fn slice(self: *const TilesMetadata) []const minesweeper.TileLocation {
        return self.tiles[0..self.len];
    }
};
const TileStatsType = union(enum) {
    na_safe,
    na_mine,
    na_unknown,
    adj: SSID,
};
const SS_SolutionBitsRange = struct {
    sbr: minesweeper.SolutionBits.SolutionBitsRange,
    ss: usize,
};
const AdjMinecountMap = struct {
    //Indices range from 0 to 8 tile and tile is a mine (9)
    map: [10]big_number.BigUInt,
    const IDX_MINE: usize = 9;
    ///init_num only affects 0-8 and is 0 for `IDX_MINE`.
    fn init(allocator: std.mem.Allocator) !AdjMinecountMap {
        var adj_mm: AdjMinecountMap = undefined;
        var adj_mm_len: usize = 0;
        for (adj_mm.map[0..10]) |*bui| {
            errdefer for (adj_mm.map[0..adj_mm_len]) |*ebui| ebui.deinit(allocator);
            bui.* = try .init(allocator, 0);
            adj_mm_len += 1;
        }
        return adj_mm;
    }
    fn clone(self: AdjMinecountMap, allocator: std.mem.Allocator) !AdjMinecountMap {
        var ret: AdjMinecountMap = undefined;
        var ret_len: usize = 0;
        for (&self.map, &ret.map) |*sbui, *retbui| {
            errdefer for (ret.map[0..ret_len]) |*ebui| ebui.deinit(allocator);
            retbui.* = try sbui.clone(allocator);
            ret_len += 1;
        }
        return ret;
    }
    /// Shift or convolve frequency of 0-8 adjacent mines with a constant `by` when counting all`.na_mine`.
    fn shift(self: *AdjMinecountMap, allocator: std.mem.Allocator, by: usize) !void {
        if (by == 0) return;
        for (0..9 - by) |old_i| {
            const rev_i = 9 - by - old_i - 1;
            const new_i = rev_i + by;
            self.map[new_i].deinit(allocator);
            self.map[new_i] = self.map[rev_i];
            self.map[rev_i] = try .init(allocator, 0);
        }
    }
    //To add all other adj_mm.
    fn add(self: *AdjMinecountMap, allocator: std.mem.Allocator, other: *const AdjMinecountMap) !void {
        for (&self.map, &other.map) |*smap, *omap|
            try smap.add(allocator, omap);
    }
    //To multiply other ss that was not part of the regions to consider.
    fn multiply(self: *AdjMinecountMap, allocator: std.mem.Allocator, other_bui: *const big_number.BigUInt) !void {
        for (&self.map) |*smap|
            try smap.multiply(allocator, other_bui);
    }
    fn convolve(self: *AdjMinecountMap, allocator: std.mem.Allocator, other: *const AdjMinecountMap) !void {
        var result: AdjMinecountMap = try .init(allocator);
        errdefer result.deinit(allocator);
        for (0..9) |i| {
            for (0..9) |j| {
                const m = i + j;
                if (m >= IDX_MINE) continue;
                const self_bui = &self.map[i];
                const other_bui = &other.map[j];
                var bui_mult: big_number.BigUInt = try self_bui.clone(allocator);
                defer bui_mult.deinit(wasm_allocator);
                try bui_mult.multiply(allocator, other_bui);
                try result.map[m].add(allocator, &bui_mult);
            }
        }
        var idx_mine_bui: big_number.BigUInt = try .init(allocator, 0);
        defer idx_mine_bui.deinit(allocator);
        const self_idx_nz = !self.map[IDX_MINE].is_zero();
        const other_idx_nz = !other.map[IDX_MINE].is_zero();
        //To add and multiply the number of combinations where the tile is a mine for IDX_MINE
        if (self_idx_nz and other_idx_nz) {
            @panic("Both self and other should not have IDX_MINE be nonzero");
        } else if (self_idx_nz) {
            for (0..9) |i| {
                var bui: big_number.BigUInt = try other.map[i].clone(allocator);
                defer bui.deinit(allocator);
                try bui.multiply(allocator, &self.map[IDX_MINE]);
                try idx_mine_bui.add(allocator, &bui);
            }
        } else if (other_idx_nz) {
            for (0..9) |i| {
                var bui: big_number.BigUInt = try self.map[i].clone(allocator);
                defer bui.deinit(allocator);
                try bui.multiply(allocator, &other.map[IDX_MINE]);
                try idx_mine_bui.add(allocator, &bui);
            }
        }
        try result.map[IDX_MINE].add(allocator, &idx_mine_bui);
        self.deinit(allocator);
        self.* = result;
    }
    pub fn format(self: AdjMinecountMap, writer: *std.io.Writer) !void {
        try writer.writeAll("AdjMinecountMap{ ");
        for (0..10) |i| {
            const bui = &self.map[i];
            try bui.format(writer);
            if (i != 9) try writer.writeAll(", ");
        }
        try writer.writeAll(" }");
    }
    fn deinit(self: *AdjMinecountMap, allocator: std.mem.Allocator) void {
        for (&self.map) |*bui| bui.deinit(allocator);
    }
};
fn sb_bit(sb: []const u32, i: usize) u1 {
    const bit_i: u5 = @truncate(i & 0b11111);
    return @intFromBool(sb[i >> 5] & (@as(u32, 1) << bit_i) != 0);
}
fn ss_sort(_: void, lhs: usize, rhs: usize) bool {
    return lhs < rhs;
}
var tile_stats_now: [10]f64 = undefined;
extern fn ReturnTileStats([*c]f64, usize) void;
fn calculate_tile_stats(x: usize, y: usize, global_mine_count: isize, include_mine_flags: bool) !void {
    if (cm.is_probability_calculated()) {
        //v is the index of the subsystem of the tile.
        var loc_hm: LocationHM = .empty;
        defer loc_hm.deinit(wasm_allocator);
        const width = cm.map_parser.?.width;
        const height = cm.map_parser.?.height;
        const tmd: TilesMetadata = .init(x, y, width, height);
        const bd = get_board_data(&cm, global_mine_count, include_mine_flags) orelse return error.InvalidBoardData;
        var mfcs = try rng.mfcs_create(&cm, bd, bd.adj_mine_count, false);
        defer mfcs.deinit(wasm_allocator);
        for (cm.mm_subsystems, 0..) |*mms, ss| {
            for (mms.tm.idtol.items) |tl| {
                try loc_hm.put(wasm_allocator, tl, .{ .id = mms.tm.ltoid.get(tl).?, .ss = ss });
            }
        }
        std.log.debug("Clicking tile ({},{})", .{ x, y });
        for (mfcs.items) |*mfc| {
            std.log.warn("{} {any} {any}\n", .{ mfc.m, mfc.f.bytes.items, mfc.mds.items });
        }
        const middle_tst: TileStatsType = v: {
            if (loc_hm.get(tmd.middle)) |ssid| {
                break :v .{ .adj = ssid };
            } else {
                const mstype = cm.map_parser.?.map.items[tmd.middle.y * width + tmd.middle.x];
                if (mstype.is_number() or mstype == .donotcare) {
                    break :v .na_safe;
                } else if (mstype == .flag or mstype == .mine) {
                    break :v .na_mine;
                } else {
                    break :v .na_unknown;
                }
            }
        };
        var tmd_tst: [8]TileStatsType = undefined;
        for (tmd_tst[0..tmd.len], tmd.slice()) |*tst, tl| {
            if (loc_hm.get(tl)) |ssid| {
                tst.* = .{ .adj = ssid };
            } else {
                const mstype = cm.map_parser.?.map.items[tl.y * width + tl.x];
                if (mstype.is_number() or mstype == .donotcare) {
                    tst.* = .na_safe;
                } else if (mstype == .flag or mstype == .mine) {
                    tst.* = .na_mine;
                } else {
                    tst.* = .na_unknown;
                }
            }
        }
        var num_unknowns: usize = 0;
        for (tmd_tst) |tst| {
            if (tst == .na_unknown) num_unknowns += 1;
        }
        var total_adj_mm: AdjMinecountMap = try .init(wasm_allocator);
        defer total_adj_mm.deinit(wasm_allocator);
        if (middle_tst == .na_unknown or middle_tst == .na_safe) {
            for (mfcs.items) |*mfc| {
                const mines_left: u32 = @truncate(@as(usize, @bitCast(bd.adj_mine_count)) - mfc.m);
                //Sum of unknown_adj_mm should be comb(#'non-adjacent tiles', 'mines left per solutions').
                var unknown_adj_mm: AdjMinecountMap = try .init(wasm_allocator);
                defer unknown_adj_mm.deinit(wasm_allocator);
                for (0..num_unknowns + 1) |r_m| {
                    unknown_adj_mm.map[r_m].deinit(wasm_allocator);
                    //Normal hypergeometric if .na_safe, otherwise altered hypergeometric if .na_unknown (+1 tile that should always be safe)
                    const unknown_adj = @intFromBool(middle_tst == .na_unknown);
                    unknown_adj_mm.map[r_m] = try hg_numerator(middle_tst == .na_unknown, bd, mines_left, @truncate(r_m), @truncate(num_unknowns + unknown_adj));
                }
                if (middle_tst == .na_unknown) {
                    const non_adj_tiles: u32 = @truncate(@as(usize, @bitCast(bd.non_adjacent_tiles)));
                    if (non_adj_tiles != 0 and mines_left != 0) {
                        unknown_adj_mm.map[AdjMinecountMap.IDX_MINE].deinit(wasm_allocator);
                        unknown_adj_mm.map[AdjMinecountMap.IDX_MINE] = try big_number.bui_comb(wasm_allocator, non_adj_tiles - 1, mines_left - 1);
                    }
                }
                var num_na_mine: usize = 0;
                for (tmd_tst[0..tmd.len]) |tst| {
                    if (tst == .na_mine) num_na_mine += 1;
                }
                try unknown_adj_mm.shift(wasm_allocator, num_na_mine);
                //At most 4 subsystems may be read in adjacent tile stats.
                var ss_arr: [4]usize = undefined;
                var ss_arr_len: usize = 0;
                for (tmd_tst[0..tmd.len]) |tst| {
                    if (tst == .adj) {
                        for (ss_arr) |ss| {
                            if (tst.adj.ss == ss) break;
                        } else {
                            ss_arr[ss_arr_len] = tst.adj.ss;
                            ss_arr_len += 1;
                        }
                    }
                }
                std.mem.sort(usize, &ss_arr, {}, ss_sort);
                //Any ss not in ss_arr will have its range length multiplied.
                var leftover_ss_bui: big_number.BigUInt = try .init(wasm_allocator, 1);
                defer leftover_ss_bui.deinit(wasm_allocator);
                next_not_used: for (0..cm.mm_subsystems.len) |ss| {
                    for (ss_arr[0..ss_arr_len]) |ss_cmp|
                        if (ss == ss_cmp) continue :next_not_used;
                    const sbr = cm.mm_subsystems[ss].sb.metadata.items[mfc.mds.items[ss]];
                    try leftover_ss_bui.multiply_byte(wasm_allocator, @truncate(sbr.end - sbr.begin));
                }
                //Used as a counter to iterate all ranges of adjacent tiles.
                var ss_sbr_arr: std.ArrayList(SS_SolutionBitsRange) = .empty;
                defer ss_sbr_arr.deinit(wasm_allocator);
                for (ss_arr[0..ss_arr_len]) |ss| {
                    const sbr = cm.mm_subsystems[ss].sb.metadata.items[mfc.mds.items[ss]];
                    try ss_sbr_arr.append(wasm_allocator, .{
                        .sbr = sbr,
                        .ss = ss,
                    });
                }
                var conv_adj_mm: AdjMinecountMap = try .init(wasm_allocator);
                defer conv_adj_mm.deinit(wasm_allocator);
                conv_adj_mm.map[0].reset(1); //0th is 1 to convolve properly.
                for (ss_sbr_arr.items) |*ss_sbr| {
                    var this_adj_bits: [8]usize = undefined;
                    var tab_len: usize = 0;
                    for (tmd_tst[0..tmd.len]) |tst| {
                        if (tst == .adj) {
                            if (tst.adj.ss == ss_sbr.ss) {
                                this_adj_bits[tab_len] = tst.adj.id;
                                tab_len += 1;
                            }
                        }
                    }
                    var adj_mm: AdjMinecountMap = try .init(wasm_allocator);
                    defer adj_mm.deinit(wasm_allocator);
                    for (ss_sbr.sbr.begin..ss_sbr.sbr.end) |i| {
                        const range_bits = cm.mm_subsystems[ss_sbr.ss].sb.get_range_bits(i);
                        var num_mines: usize = 0;
                        for (this_adj_bits[0..tab_len]) |bit| num_mines += sb_bit(range_bits, bit);
                        try adj_mm.map[num_mines].add_one(wasm_allocator);
                    }
                    try conv_adj_mm.convolve(wasm_allocator, &adj_mm);
                }
                var unknown_conv_adj_mm: AdjMinecountMap = try unknown_adj_mm.clone(wasm_allocator);
                defer unknown_conv_adj_mm.deinit(wasm_allocator);
                try unknown_conv_adj_mm.convolve(wasm_allocator, &conv_adj_mm);
                try unknown_conv_adj_mm.multiply(wasm_allocator, &leftover_ss_bui);
                try total_adj_mm.add(wasm_allocator, &unknown_conv_adj_mm);
            }
        } else if (middle_tst == .na_mine) {
            try total_adj_mm.map[AdjMinecountMap.IDX_MINE].add_one(wasm_allocator);
        }
        std.log.warn("total_adj_mm: {f}\n", .{total_adj_mm});
        var sum_bui: big_number.BigUInt = try .init(wasm_allocator, 0);
        defer sum_bui.deinit(wasm_allocator);
        for (0..10) |m|
            try sum_bui.add(wasm_allocator, &total_adj_mm.map[m]);
        const sum_bui_float = sum_bui.to_float(f64);
        for (0..10) |m|
            tile_stats_now[m] = total_adj_mm.map[m].to_float(f64) / sum_bui_float;
        ReturnTileStats(&tile_stats_now, y * width + x);
    } else {
        const err_msg = std.fmt.allocPrint(wasm_allocator, "Board has been edited. Use 'Calculate Probability' again to remove this error.", .{}) catch return error.OutOfMemory;
        rng.add_error_slice(err_msg);
        return error.InvalidBoardData;
    }
}
export fn CalculateTileStats(x: usize, y: usize, global_mine_count: isize, include_mine_flags: bool) [*c]StringSlice {
    defer @import("wasm_print.zig").FlushPrint(false);
    calculate_tile_stats(x, y, global_mine_count, include_mine_flags) catch |e| {
        switch (e) {
            error.OutOfMemory => {
                @panic("Allocation error.");
            },
            error.InvalidBoardData => {
                return &rng.error_slice;
            },
        }
    };
    return 0;
}
pub extern fn ClearResults() void;
pub extern fn AppendResults([*c]const u8, usize) void;
pub extern fn FinalizeResults() void;
pub extern fn SetSubsystemNumber(usize) void;
pub extern fn SetTimeoutProgress(usize, f32) void;
pub export var CalculateStatus: bool = false;
pub export var CancelCalculation: bool = false;
