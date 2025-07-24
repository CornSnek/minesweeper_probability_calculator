const std = @import("std");
const sorted_list = @import("sorted_list.zig");
const big_number = @import("big_number.zig");
const UsingWasm = @import("builtin").os.tag == .freestanding;
pub const TileLocation = extern struct {
    x: usize,
    y: usize,
};
pub const MsType = enum {
    ///Unchecked tile
    unknown,
    mine,
    flag,
    ///Numbered tile, but is not scanned for mine information or adjacent unknown tiles near it.
    donotcare,
    @"0",
    @"1",
    @"2",
    @"3",
    @"4",
    @"5",
    @"6",
    @"7",
    @"8",
    pub fn init(ch: u8) ?MsType {
        return switch (ch) {
            'c' => .unknown,
            'v' => .mine,
            'f' => .flag,
            'x' => .donotcare,
            '0'...'8' => |num| @enumFromInt((num - '0') + @intFromEnum(@as(MsType, .@"0"))),
            else => null,
        };
    }
    ///Inverse of init.
    pub fn js_ch(self: MsType) []const u8 {
        return switch (self) {
            .unknown => "c",
            .mine => "v",
            .flag => "f",
            .donotcare => "x",
            inline else => |e| {
                const num_mines = e.number_of_mines();
                std.debug.assert(num_mines != null);
                const array_ch = "012345678";
                return array_ch[num_mines.? .. num_mines.? + 1];
            },
        };
    }
    pub fn number_of_mines(self: MsType) ?u4 {
        return switch (self) {
            .@"0", .@"1", .@"2", .@"3", .@"4", .@"5", .@"6", .@"7", .@"8" => |e| @intFromEnum(e) - @intFromEnum(@as(MsType, .@"0")),
            else => null,
        };
    }
    pub fn is_clicked(self: MsType) bool {
        return switch (self) {
            .mine, .donotcare, .@"0", .@"1", .@"2", .@"3", .@"4", .@"5", .@"6", .@"7", .@"8" => true,
            else => false,
        };
    }
    pub fn is_number(self: MsType) bool {
        return switch (self) {
            .@"0", .@"1", .@"2", .@"3", .@"4", .@"5", .@"6", .@"7", .@"8" => true,
            else => false,
        };
    }
    pub fn in_palette(self: MsType) bool {
        return switch (self) {
            .unknown, .mine, .flag, .donotcare, .@"0", .@"1", .@"2", .@"3", .@"4", .@"5", .@"6", .@"7", .@"8" => true,
        };
    }
    pub fn description(self: MsType) []const u8 {
        return switch (self) {
            .unknown => "Unknown Tile - Tile that has not been clicked yet.",
            .mine => "Mine Tile - Tile that has been clicked and is a mine. Flag Tile is similar to this to decrease number tiles by 1 for probability calculations.",
            .flag => "Flag Tile - Tile that is assumed to be a mine. Mine Tile is similar to this to decrease number tiles by 1 for probability calculations.",
            .donotcare => "X Tile - Tile that is clicked as a safe number tile, but adjacent tiles will not be scanned for probability calculations.",
            .@"0" => "0 Tile - Tile that has exactly 0 mines around its sides.",
            .@"1" => "1 Tile - Tile that has exactly 1 mine around its sides.",
            .@"2" => "2 Tile - Tile that has exactly 2 mines around its sides.",
            .@"3" => "3 Tile - Tile that has exactly 3 mines around its sides.",
            .@"4" => "4 Tile - Tile that has exactly 4 mines around its sides.",
            .@"5" => "5 Tile - Tile that has exactly 5 mines around its sides.",
            .@"6" => "6 Tile - Tile that has exactly 6 mines around its sides.",
            .@"7" => "7 Tile - Tile that has exactly 7 mines around its sides.",
            .@"8" => "8 Tile - Tile that has exactly 8 mines around its sides.",
        };
    }
    pub fn image_url(self: MsType) []const u8 {
        return switch (self) {
            .unknown => "unknown.svg",
            .mine => "mine.svg",
            .flag => "flag.svg",
            .donotcare => "x.svg",
            .@"0" => "0.svg",
            .@"1" => "1.svg",
            .@"2" => "2.svg",
            .@"3" => "3.svg",
            .@"4" => "4.svg",
            .@"5" => "5.svg",
            .@"6" => "6.svg",
            .@"7" => "7.svg",
            .@"8" => "8.svg",
        };
    }
};
pub const MapParser = struct {
    pub const State = enum { no_width, has_width };
    pub const InitStatus = union(enum) {
        ok: MapParser,
        alloc_error,
        parse_error,
        invalid_char: usize,
    };
    map: std.ArrayListUnmanaged(MsType) = .empty,
    width: usize,
    height: usize,
    pub fn init(allocator: std.mem.Allocator, width: usize, height: usize) InitStatus {
        var mm: MapParser = .{ .width = width, .height = height };
        mm.map.appendNTimes(allocator, MsType.unknown, width * height) catch return .alloc_error;
        return .{ .ok = mm };
    }
    pub fn init_parse(str: []const u8, allocator: std.mem.Allocator) InitStatus {
        var mm: MapParser = .{ .width = undefined, .height = 0 };
        var state: State = .no_width;
        var it = std.mem.tokenizeScalar(u8, str, '\n');
        while (it.next()) |line| {
            switch (state) {
                .no_width => {
                    mm.width = line.len;
                    state = .has_width;
                },
                else => {
                    if (line.len != mm.width) {
                        mm.deinit(allocator);
                        return .parse_error;
                    }
                },
            }
            for (line) |ch| {
                if (ch == '\r') continue;
                const i_now = mm.map.items.len;
                mm.map.append(allocator, MsType.init(ch) orelse {
                    mm.deinit(allocator);
                    return .{ .invalid_char = i_now };
                }) catch {
                    mm.deinit(allocator);
                    return .alloc_error;
                };
            }
            mm.height += 1;
        }
        return .{ .ok = mm };
    }
    fn create_term(allocator: std.mem.Allocator, lc: *LinearCombination, id: ?u31, v: i32) !void {
        const num_mines_t = try allocator.create(Term);
        num_mines_t.* = .{ .id = id, .v = v };
        std.debug.assert(lc.insert(num_mines_t) == .ok);
    }
    pub fn query_tile(self: MapParser, x: usize, y: usize) ?MsType {
        if (x >= self.width or y >= self.height) return null;
        const i: usize = y * self.width + x;
        return self.map.items[i];
    }
    pub fn set_tile(self: *MapParser, x: usize, y: usize, tile: usize) !void {
        if (x >= self.width or y >= self.height) return error.LocationOutOfRange;
        if (tile >= @typeInfo(MsType).@"enum".fields.len) return error.TileOutOfRange;
        const i: usize = y * self.width + x;
        self.map.items[i] = @enumFromInt(tile);
    }
    ///For each row containing a number, scan for adjacent unknowns rotating clockwise starting upwards
    pub fn to_minesweeper_matrix(self: MapParser, allocator: std.mem.Allocator) !MinesweeperMatrix {
        var mm: MinesweeperMatrix = .empty;
        errdefer mm.deinit(allocator);
        for (0..self.map.items.len) |i| {
            const mstype = self.map.items[i];
            const x = i % self.width;
            const y = i / self.width;
            if (mstype.number_of_mines()) |num_mines| {
                const xgt0 = x > 0;
                const xltw = x < self.width - 1;
                const ygt0 = y > 0;
                const ylth = y < self.height - 1;
                var adj_mines: i31 = num_mines;
                var lc: LinearCombination = .empty_alloc;
                errdefer lc.deinit(allocator);
                const max_len = self.map.items.len;
                const has_n = ygt0;
                const has_ne = xltw and ygt0 and i + 1 - self.width < max_len;
                const has_e = xltw and i + 1 < max_len;
                const has_se = xltw and ylth and i + 1 + self.width < max_len;
                const has_s = ylth and i + self.width < max_len;
                const has_sw = xgt0 and ylth and i - 1 + self.width < max_len;
                const has_w = xgt0;
                const has_nw = xgt0 and ygt0;
                if (has_n) {
                    const tile = self.map.items[i - self.width];
                    if (tile == .flag or tile == .mine)
                        adj_mines -= 1;
                }
                if (has_ne) {
                    const tile = self.map.items[i + 1 - self.width];
                    if (tile == .flag or tile == .mine)
                        adj_mines -= 1;
                }
                if (has_e) {
                    const tile = self.map.items[i + 1];
                    if (tile == .flag or tile == .mine)
                        adj_mines -= 1;
                }
                if (has_se) {
                    const tile = self.map.items[i + 1 + self.width];
                    if (tile == .flag or tile == .mine)
                        adj_mines -= 1;
                }
                if (has_s) {
                    const tile = self.map.items[i + self.width];
                    if (tile == .flag or tile == .mine)
                        adj_mines -= 1;
                }
                if (has_sw) {
                    const tile = self.map.items[i - 1 + self.width];
                    if (tile == .flag or tile == .mine)
                        adj_mines -= 1;
                }
                if (has_w) {
                    const tile = self.map.items[i - 1];
                    if (tile == .flag or tile == .mine)
                        adj_mines -= 1;
                }
                if (has_nw) {
                    const tile = self.map.items[i - 1 - self.width];
                    if (tile == .flag or tile == .mine)
                        adj_mines -= 1;
                }
                if (has_n and self.map.items[i - self.width] == .unknown) {
                    const id = try mm.tm.insert(allocator, .{ .x = x, .y = y - 1 });
                    try create_term(allocator, &lc, @truncate(id), 1);
                }
                if (has_ne and self.map.items[i + 1 - self.width] == .unknown) {
                    const id = try mm.tm.insert(allocator, .{ .x = x + 1, .y = y - 1 });
                    try create_term(allocator, &lc, @truncate(id), 1);
                }
                if (has_e and self.map.items[i + 1] == .unknown) {
                    const id = try mm.tm.insert(allocator, .{ .x = x + 1, .y = y });
                    try create_term(allocator, &lc, @truncate(id), 1);
                }
                if (has_se and self.map.items[i + 1 + self.width] == .unknown) {
                    const id = try mm.tm.insert(allocator, .{ .x = x + 1, .y = y + 1 });
                    try create_term(allocator, &lc, @truncate(id), 1);
                }
                if (has_s and self.map.items[i + self.width] == .unknown) {
                    const id = try mm.tm.insert(allocator, .{ .x = x, .y = y + 1 });
                    try create_term(allocator, &lc, @truncate(id), 1);
                }
                if (has_sw and self.map.items[i - 1 + self.width] == .unknown) {
                    const id = try mm.tm.insert(allocator, .{ .x = x - 1, .y = y + 1 });
                    try create_term(allocator, &lc, @truncate(id), 1);
                }
                if (has_w and self.map.items[i - 1] == .unknown) {
                    const id = try mm.tm.insert(allocator, .{ .x = x - 1, .y = y });
                    try create_term(allocator, &lc, @truncate(id), 1);
                }
                if (has_nw and self.map.items[i - 1 - self.width] == .unknown) {
                    const id = try mm.tm.insert(allocator, .{ .x = x - 1, .y = y - 1 });
                    try create_term(allocator, &lc, @truncate(id), 1);
                }
                try create_term(allocator, &lc, null, adj_mines);
                try mm.append(allocator, lc);
            }
        }
        return mm;
    }
    pub fn as_str(self: MapParser, allocator: std.mem.Allocator) ![]u8 {
        var str_list: std.ArrayListUnmanaged(u8) = .empty;
        defer str_list.deinit(allocator);
        const width = self.width;
        var width_counter: usize = 0;
        for (self.map.items) |mst| {
            width_counter = (width_counter + 1) % width;
            try str_list.append(allocator, mst.js_ch()[0]);
            if (width_counter == 0) {
                try str_list.append(allocator, '\n');
            }
        }
        return try str_list.toOwnedSlice(allocator);
    }
    pub fn deinit(self: *MapParser, allocator: std.mem.Allocator) void {
        self.map.deinit(allocator);
    }
};
pub const TileMap = struct {
    pub const LocationToID = std.AutoHashMapUnmanaged(TileLocation, usize);
    ltoid: LocationToID = .empty,
    idtol: std.ArrayListUnmanaged(TileLocation) = .empty,
    pub const empty: TileMap = .{};
    ///For js to interact with the .idtol array.
    pub const IDToLocationExtern = extern struct {
        ptr: [*c]TileLocation,
        len: usize,
        pub const empty: IDToLocationExtern = .{ .ptr = 0, .len = 0 };
    };
    ///Insert uniques only and returns id of the tile.
    pub fn insert(self: *TileMap, allocator: std.mem.Allocator, tl: TileLocation) !usize {
        const ltoidgop = try self.ltoid.getOrPut(allocator, tl);
        if (!ltoidgop.found_existing) {
            ltoidgop.value_ptr.* = self.idtol.items.len;
            try self.idtol.append(allocator, tl);
        }
        return ltoidgop.value_ptr.*;
    }
    pub fn get_id(self: TileMap, tl: TileLocation) ?usize {
        return self.ltoid.get(tl);
    }
    pub fn get_location(self: TileMap, id: usize) ?TileLocation {
        return if (id >= self.idtol.items.len) null else self.idtol.items[id];
    }
    /// Get all locations of this tile map. This struct owns the memory.
    pub fn get_id_to_location_extern(self: TileMap) IDToLocationExtern {
        return .{ .ptr = self.idtol.items.ptr, .len = self.idtol.items.len };
    }
    pub fn deinit(self: *TileMap, allocator: std.mem.Allocator) void {
        self.ltoid.deinit(allocator);
        self.idtol.deinit(allocator);
    }
};
pub const SolutionBits = struct {
    data: std.ArrayListUnmanaged(u32),
    number_bytes: u32,
    pub const empty: SolutionBits = .{ .data = .empty, .number_bytes = 0 };
    pub const SolutionBitsExtern = extern struct {
        ptr: [*c]u32,
        len: usize,
        number_bytes: u32,
        pub const empty: SolutionBitsExtern = .{ .ptr = 0, .len = 0, .number_bytes = 0 };
    };
    pub fn get_solution_bits_extern(self: SolutionBits) SolutionBitsExtern {
        return .{ .ptr = self.data.items.ptr, .len = self.data.items.len, .number_bytes = self.number_bytes };
    }
    pub fn deinit(self: *SolutionBits, allocator: std.mem.Allocator) void {
        self.data.deinit(allocator);
    }
};
/// All LinearCombination must have .alloc_all true and valid order (.id from ascending order with exactly one null).
pub const MinesweeperMatrix = struct {
    lcs: std.ArrayListUnmanaged(LinearCombination),
    tm: TileMap,
    sb: SolutionBits,
    pub const empty: MinesweeperMatrix = .{ .lcs = .empty, .tm = .empty, .sb = .empty };
    pub fn append(self: *MinesweeperMatrix, allocator: std.mem.Allocator, lc: LinearCombination) !void {
        if (!lc.alloc_all) return error.MustBeAllocated;
        if (!lc.valid_order()) return error.MustBeValidLC;
        try self.lcs.append(allocator, lc);
    }
    pub const ValuesList = std.ArrayListUnmanaged(i32);
    pub const LocationCount = extern struct {
        x: usize,
        y: usize,
        count: i32,
        mf_ptr: [*c]MineFrequency,
        mf_len: usize,
        pub fn deinit(self: LocationCount, allocator: std.mem.Allocator) void {
            allocator.free(self.mf_ptr[0..self.mf_len]);
        }
    };
    pub const MineFrequency = extern struct {
        m: usize,
        f: usize = 0,
        pub const Context = struct {
            pub fn lt(a: MineFrequency, b: MineFrequency) bool {
                return a.m < b.m;
            }
            pub fn eq(a: MineFrequency, b: MineFrequency) bool {
                return a.m == b.m;
            }
        };
    };
    pub const MineFrequencyMap = sorted_list.SortedList(MineFrequency, MineFrequency.Context);
    pub const ProbabilityList = extern struct {
        total: usize,
        mf_ptr: [*c]MineFrequency,
        mf_len: usize,
        lc_ptr: [*c]LocationCount,
        lc_len: usize,
        pub const empty: ProbabilityList = .{ .total = 0, .lc_ptr = 0, .lc_len = 0, .mf_ptr = 0, .mf_len = 0 };
        pub fn init(
            allocator: std.mem.Allocator,
            total: usize,
            total_mf_map: *MineFrequencyMap,
            tm: TileMap,
            valuesl: *ValuesList,
            location_mf_map: *std.ArrayListUnmanaged(MineFrequencyMap),
        ) !ProbabilityList {
            std.debug.assert(tm.idtol.items.len == valuesl.items.len);
            var pl: ProbabilityList = undefined;
            pl.total = total;
            //Because of extern struct, separate the ptr and len from slices.
            const total_mf_arr = try total_mf_map.list.toOwnedSlice(allocator);
            errdefer allocator.free(total_mf_arr);
            pl.mf_ptr = total_mf_arr.ptr;
            pl.mf_len = total_mf_arr.len;
            const lc_arr = try allocator.alloc(LocationCount, tm.idtol.items.len);
            errdefer allocator.free(lc_arr);
            pl.lc_ptr = lc_arr.ptr;
            pl.lc_len = lc_arr.len;
            for (0..tm.idtol.items.len) |i| {
                const mf_arr = try location_mf_map.items[i].list.toOwnedSlice(allocator);
                lc_arr[i] = .{
                    .x = tm.idtol.items[i].x,
                    .y = tm.idtol.items[i].y,
                    .count = valuesl.items[i],
                    .mf_ptr = mf_arr.ptr,
                    .mf_len = mf_arr.len,
                };
            }
            return pl;
        }
        pub fn deinit(self: ProbabilityList, allocator: std.mem.Allocator) void {
            if (self.lc_ptr != 0) { //self.mf_ptr is also implicitly 0
                allocator.free(self.mf_ptr[0..self.mf_len]);
                const lc_arr = self.lc_ptr[0..self.lc_len];
                for (lc_arr) |lc|
                    lc.deinit(allocator);
                allocator.free(lc_arr);
            }
        }
    };
    pub fn separate_subsystems(self: MinesweeperMatrix, allocator: std.mem.Allocator) ![]MinesweeperMatrix {
        var graph: std.AutoHashMapUnmanaged(u31, sorted_list.SortedIntList(u31, .lt)) = .empty;
        defer {
            var graph_it = graph.iterator();
            while (graph_it.next()) |kv| {
                kv.value_ptr.deinit(allocator);
            }
            graph.deinit(allocator);
        }
        for (self.lcs.items) |lc| { //Create a bi-directional graph for the ids except null.
            if (!lc.valid_order()) return error.MustBeValidLC;
            var prev: ?*const Term = null;
            var next: ?*const Term = lc.head;
            while (next) |n| {
                if (n.id) |nid| {
                    if (prev) |p| {
                        if (p.id) |pid| {
                            const pton_gop = try graph.getOrPut(allocator, pid);
                            if (!pton_gop.found_existing) pton_gop.value_ptr.* = .empty;
                            _ = try pton_gop.value_ptr.insert_unique(allocator, nid);
                            const ntop_gop = try graph.getOrPut(allocator, nid);
                            if (!ntop_gop.found_existing) ntop_gop.value_ptr.* = .empty;
                            _ = try ntop_gop.value_ptr.insert_unique(allocator, pid);
                        } else break;
                    }
                } else break;
                prev = next;
                next = n.next;
            }
        }
        const IDCounter = struct {
            id: u31,
            i: u32 = 0,
        };
        var subsystem_sets: std.AutoHashMapUnmanaged(u31, std.ArrayListUnmanaged(usize)) = .empty;
        defer {
            var sss_it = subsystem_sets.iterator();
            while (sss_it.next()) |kv| {
                kv.value_ptr.deinit(allocator);
            }
            subsystem_sets.deinit(allocator);
        }
        //DFS for the lowest_id each LinearCombination can go to.
        //It determines which subsystem it belongs to.
        for (self.lcs.items, 0..) |lc, lc_id| {
            if (lc.head.?.id == null) { //Edge case where it's just R.H.S only.
                if (lc.head.?.v != 0) {
                    return error.NoSolutions;
                } else continue;
            }
            var lowest_id: u31 = lc.head.?.id.?;
            var id_counters: std.ArrayListUnmanaged(IDCounter) = .empty;
            defer id_counters.deinit(allocator);
            var visited: std.AutoHashMapUnmanaged(u31, void) = .empty;
            defer visited.deinit(allocator);
            try id_counters.append(allocator, .{ .id = lowest_id });
            try visited.put(allocator, lowest_id, {});
            while (id_counters.items.len != 0) {
                const idc_last = &id_counters.items[id_counters.items.len - 1];
                const nextlist = graph.get(idc_last.id) orelse break; //Edge case where only one id.
                if (idc_last.i == nextlist.list.items.len) {
                    _ = id_counters.pop();
                    continue;
                }
                const next_to_visit = nextlist.list.items[idc_last.i];
                if (!visited.contains(next_to_visit)) {
                    lowest_id = @min(lowest_id, next_to_visit);
                    try visited.put(allocator, next_to_visit, {});
                    try id_counters.append(allocator, .{ .id = next_to_visit });
                }
                idc_last.i += 1;
            }
            const sss_gop = try subsystem_sets.getOrPut(allocator, lowest_id);
            if (!sss_gop.found_existing) sss_gop.value_ptr.* = .empty;
            try sss_gop.value_ptr.append(allocator, lc_id);
        }
        const sss_count = subsystem_sets.size;
        const mm_subsystems = try allocator.alloc(MinesweeperMatrix, sss_count);
        for (mm_subsystems) |*mm| mm.* = .empty;
        errdefer {
            for (mm_subsystems) |*mm| {
                mm.deinit(allocator);
            }
            allocator.free(mm_subsystems);
        }
        var mm_i: usize = 0;
        var sss_it = subsystem_sets.iterator();
        while (sss_it.next()) |kv| { //Change IDs of subsystems so that they all start at ID#0, 1, 2, ...
            var id_old_to_new: std.AutoHashMapUnmanaged(u31, u31) = .empty;
            defer id_old_to_new.deinit(allocator);
            const scan_lc_ids = kv.value_ptr.items;
            for (scan_lc_ids) |lc_id| {
                const lc = self.lcs.items[lc_id];
                try mm_subsystems[mm_i].append(allocator, try lc.clone(allocator));
                var next: ?*const Term = lc.head;
                while (next) |n| {
                    const old_id = n.id orelse break;
                    const gop = try id_old_to_new.getOrPut(allocator, old_id);
                    if (!gop.found_existing) gop.value_ptr.* = @truncate(try mm_subsystems[mm_i].tm.insert(allocator, self.tm.get_location(old_id).?));
                    next = n.next;
                }
            }
            for (mm_subsystems[mm_i].lcs.items) |*lc| {
                var next: ?*Term = lc.head;
                while (next) |n| {
                    n.id = id_old_to_new.get(n.id orelse break).?;
                    next = n.next;
                }
            }
            mm_i += 1;
        }
        return mm_subsystems;
    }
    fn solve_rref(self: *MinesweeperMatrix, allocator: std.mem.Allocator) !void {
        for (self.lcs.items) |lc| {
            var next: ?*const Term = lc.head;
            while (next) |n| {
                if (n.id == null) {
                    if (n.v >= 0) break;
                    return error.OverFlag;
                }
                next = n.next;
            }
        }
        var least_id_now: u32 = 0;
        var pivot_row: usize = 0;
        while (true) : (pivot_row += 1) {
            var least_id: ?u32 = null;
            var least_id_v: i32 = undefined;
            var at_row: usize = undefined;
            next_row: for (pivot_row..self.lcs.items.len) |i| {
                var t_op = self.lcs.items[i].head;
                while (t_op) |t| {
                    if (t.id) |tid| {
                        if (least_id == null) {
                            least_id = tid;
                            least_id_v = t.v;
                            at_row = i;
                            continue :next_row;
                        } else if (tid < least_id.?) {
                            least_id = tid;
                            least_id_v = t.v;
                            at_row = i;
                            continue :next_row;
                        } else {
                            t_op = t.next;
                            continue;
                        }
                    } else { //Search until null .id
                        continue :next_row;
                    }
                    t_op = t.next;
                }
            }
            least_id_now = least_id orelse break;
            if (at_row != pivot_row) {
                std.mem.swap(LinearCombination, &self.lcs.items[at_row], &self.lcs.items[pivot_row]);
            }
            const lc_pivot_row = &self.lcs.items[pivot_row];
            const pivot_row_v = lc_pivot_row.head.?.v;
            if (pivot_row_v != 1)
                lc_pivot_row.div_exact_row(pivot_row_v);
            //Subtract pivot element for bottom rows.
            for (pivot_row + 1..self.lcs.items.len) |i| {
                const lc_other_row = &self.lcs.items[i];
                const lc_or_head = lc_other_row.head.?;
                if (lc_or_head.id) |lc_or_head_id| {
                    if (lc_or_head_id == least_id) {
                        const or_v = lc_other_row.head.?.v;
                        try lc_other_row.mult_add(allocator, lc_pivot_row, or_v * -1);
                    }
                }
            }
            //Subtract pivot element for top rows.
            for (0..pivot_row) |i| {
                const lc_other_row = &self.lcs.items[i];
                var lc_or_next = lc_other_row.head;
                while (lc_or_next) |lcorn| {
                    if (lcorn.id) |lcrid| {
                        if (lcrid == least_id) {
                            const or_v = lcorn.v;
                            try lc_other_row.mult_add(allocator, lc_pivot_row, or_v * -1);
                        }
                    } else break;
                    lc_or_next = lcorn.next;
                }
            }
        }
    }
    pub fn solve(self: *MinesweeperMatrix, allocator: std.mem.Allocator, subsystem_id: usize) !ProbabilityList {
        try self.solve_rref(allocator);
        var mines_value_list: ValuesList = .empty;
        defer mines_value_list.deinit(allocator);
        try mines_value_list.appendNTimes(allocator, 0, self.tm.idtol.items.len);
        var location_mf_map: std.ArrayListUnmanaged(MineFrequencyMap) = .empty;
        defer {
            for (location_mf_map.items) |*mf|
                mf.deinit(allocator);
            location_mf_map.deinit(allocator);
        }
        try location_mf_map.appendNTimes(allocator, .empty, self.tm.idtol.items.len);
        var total_mf_map: MineFrequencyMap = .empty;
        defer total_mf_map.deinit(allocator);
        if (self.tm.idtol.items.len != 0) {
            var free_map: std.ArrayListUnmanaged(u32) = .empty;
            defer free_map.deinit(allocator);
            try free_map.ensureTotalCapacityPrecise(allocator, self.tm.idtol.items.len);
            for (0..self.tm.idtol.items.len) |i| free_map.appendAssumeCapacity(@truncate(i));
            var total_free_count: usize = self.tm.idtol.items.len;
            for (0..self.lcs.items.len) |i| {
                const rev_i = self.lcs.items.len - 1 - i;
                const lc = self.lcs.items[rev_i];
                if (lc.head) |lch| {
                    if (lch.id) |lchid| { //Remove highest pivot ids first to swap remove.
                        _ = free_map.swapRemove(lchid);
                        total_free_count -= 1;
                    } else {
                        if (lch.v != 0) //Invalid matrix if any row has all id values (LHS) of zero and RHS (null id) is non-zero.
                            return error.NoSolutionsFound;
                    }
                }
            }
            std.sort.block(u32, free_map.items, {}, struct {
                fn f(_: void, lhs: u32, rhs: u32) bool {
                    return lhs < rhs;
                }
            }.f);
            var bui_free_max: big_number.BigUInt = try .init(allocator, 0);
            defer bui_free_max.deinit(allocator);
            var bui_free_counter: big_number.BigUInt = try .init(allocator, 0);
            defer bui_free_counter.deinit(allocator);
            try bui_free_max.pad(allocator, (total_free_count + 31) / 32);
            try bui_free_counter.pad(allocator, (total_free_count + 31) / 32);
            bui_free_max.set(total_free_count);
            self.sb.number_bytes = (self.tm.idtol.items.len + 31) / 32;
            var total: usize = 0;
            while (bui_free_counter.order(bui_free_max) != .eq) : (try bui_free_counter.add_one(allocator)) {
                if (UsingWasm) {
                    const wasm_main = @import("wasm_main.zig"); //Inside UsingWasm to prevent zig build test from reading wasm_allocator (error)
                    if (@atomicLoad(bool, &wasm_main.CalculateStatus, .acquire)) {
                        @atomicStore(bool, &wasm_main.CalculateStatus, false, .release);
                        wasm_main.SetTimeoutProgress(subsystem_id, bui_free_counter.to_float(f32) / bui_free_max.to_float(f32));
                        if (@atomicLoad(bool, &wasm_main.CancelCalculation, .acquire)) {
                            return error.CalculationCancelled;
                        }
                    }
                }
                var bui_solution: big_number.BigUInt = try .init(allocator, 0);
                defer bui_solution.deinit(allocator);
                try bui_solution.pad(allocator, self.sb.number_bytes);
                for (free_map.items, 0..) |offset, i| //Set bit of free variables to 1 (mine) if bui_free_counter is 1.
                    if (bui_free_counter.bit(i))
                        bui_solution.set(offset);
                if (try self.verify_solution(allocator, &bui_solution)) {
                    try self.sb.data.appendSlice(allocator, bui_solution.bytes.items);
                    for (0..self.tm.idtol.items.len) |id|
                        mines_value_list.items[id] += @intFromBool(bui_solution.bit(id));
                    if (UsingWasm) {
                        const pop_count = bui_solution.pop_count();
                        _ = try total_mf_map.insert_unique(allocator, .{ .m = pop_count });
                        const mf_i = total_mf_map.search(.{ .m = pop_count }).?;
                        total_mf_map.list.items[mf_i].f += 1;
                        for (0..self.tm.idtol.items.len) |id| {
                            if (bui_solution.bit(id)) {
                                _ = try location_mf_map.items[id].insert_unique(allocator, .{ .m = pop_count });
                                const l_mf_i = location_mf_map.items[id].search(.{ .m = pop_count }).?;
                                location_mf_map.items[id].list.items[l_mf_i].f += 1;
                            }
                        }
                    }
                    total += 1;
                }
            }
            if (UsingWasm) {
                var results_str: std.ArrayListUnmanaged(u8) = .empty;
                defer results_str.deinit(allocator);
                try results_str.writer(allocator).print("Total valid solutions found for this subsystem: {}<br>", .{total});
                for (total_mf_map.list.items) |mf| {
                    try results_str.writer(allocator).print("{} solution(s) have {} total mines.<br>", .{ mf.f, mf.m });
                }
                const wasm_main = @import("wasm_main.zig");
                wasm_main.AppendResults(results_str.items.ptr, results_str.items.len);
                //This code shows the mine frequencies for each subsystem
                //for (location_mf_map.items, 0..) |lmf, id| {
                //    std.log.debug("ID #{}: ", .{id});
                //    for (lmf.list.items) |mf| {
                //        std.log.debug("{{ .m={}, .f={} }}, ", .{ mf.m, mf.f });
                //    }
                //    std.log.debug("\n", .{});
                //}
            }
            return try ProbabilityList.init(allocator, total, &total_mf_map, self.tm, &mines_value_list, &location_mf_map);
        }
        return try ProbabilityList.init(allocator, 0, &total_mf_map, self.tm, &mines_value_list, &location_mf_map);
    }
    fn verify_solution(self: MinesweeperMatrix, allocator: std.mem.Allocator, bui_solution: *big_number.BigUInt) !bool {
        for (0..self.lcs.items.len) |i| {
            const rev_i = self.lcs.items.len - 1 - i;
            var lc = try self.lcs.items[rev_i].clone(allocator);
            defer lc.deinit(allocator);
            var next = lc.head;
            var pivot_term: *Term = undefined;
            var num_mines_term: *Term = undefined;
            if (next) |n| {
                if (n.id == null) {
                    if (n.v != 0) {
                        //Invalid solution if all id values (LHS) is zero and RHS (null id) is non-zero.
                        return false;
                    } else continue;
                }
                pivot_term = n;
                var next2 = next.?.next;
                next = next.?.next;
                while (next2) |n2| {
                    if (n2.id == null) {
                        num_mines_term = n2;
                        break;
                    }
                    next2 = n2.next;
                }
            }
            while (next) |n| {
                if (n.id == null) break;
                const var_v: i32 = @intFromBool(bui_solution.bit(n.id.?));
                num_mines_term.v -= n.v * var_v; //Substitute all free variables onto null id.
                lc.remove(allocator, n.id);
                next = n.next;
            }
            const pivot_v = next.?.v;
            if (pivot_v != 0 and pivot_v != 1) {
                //Invalid solution if pivot variable is not 0 (clear) or 1 (mine).
                return false;
            } else if (pivot_v == 1)
                bui_solution.set(pivot_term.id.?);
        }
        return true;
    }
    pub fn format(self: MinesweeperMatrix, comptime f: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.writeAll("MinesweeperMatrix{[");
        const pretty_print = std.mem.eql(u8, f, "p");
        for (self.lcs.items, 0..) |lc, i| {
            if (pretty_print) try writer.writeAll("\n\t");
            try writer.writeByte('[');
            try lc.format(f, options, writer);
            try writer.writeByte(']');
            if (i != self.lcs.items.len - 1) {
                try writer.writeAll(", ");
            }
        }
        if (pretty_print) try writer.writeByte('\n');
        try writer.writeAll("], ");
        if (pretty_print) try writer.writeAll("\n\t");
        for (self.tm.idtol.items, 0..self.tm.idtol.items.len) |loc, i| {
            try writer.print("ID#{} = ({},{})", .{ i, loc.x, loc.y });
            if (i != self.tm.idtol.items.len - 1) {
                try writer.writeAll(", ");
            }
        }
        if (pretty_print) try writer.writeByte('\n');
        try writer.writeByte('}');
        if (pretty_print) try writer.writeByte('\n');
    }
    pub fn deinit(self: *MinesweeperMatrix, allocator: std.mem.Allocator) void {
        self.tm.deinit(allocator);
        for (self.lcs.items) |lc| {
            lc.deinit(allocator);
        }
        self.lcs.deinit(allocator);
        self.sb.deinit(allocator);
    }
};
/// LinearCombination.ids Ordered from 0, 1, 2,... n and then null as number of mines
pub const LinearCombination = struct {
    head: ?*Term = null,
    alloc_all: bool = false,
    pub const empty: LinearCombination = .{};
    pub const empty_alloc: LinearCombination = .{ .alloc_all = true };
    pub fn init_minesweeper_row(
        allocator: std.mem.Allocator,
        id_arr: []const u31,
        num_mines: i32,
    ) !LinearCombination {
        var lc: LinearCombination = .empty_alloc;
        errdefer lc.deinit(allocator);
        for (id_arr) |id| {
            const t = try allocator.create(Term);
            t.* = .{ .id = id, .v = 1 };
            const status = lc.insert(t);
            if (status != .ok) {
                return error.DuplicateID;
            }
        }
        const nmt = try allocator.create(Term);
        nmt.* = .{ .id = null, .v = num_mines };
        _ = lc.insert(nmt);
        return lc;
    }
    pub fn format(self: LinearCombination, comptime _: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        var next: ?*const Term = self.head;
        while (next) |n| {
            try writer.writeByte('(');
            try std.fmt.formatInt(n.v, 10, .lower, options, writer);
            if (n.id) |id| {
                try writer.print(" * ID#{}", .{id});
            } else {
                try writer.writeAll(" mines");
            }
            try writer.writeByte(')');
            next = n.next;
            if (next != null) {
                try writer.writeAll(" + ");
            }
        }
    }
    const InsertStatus = enum { ok, err_equal };
    pub fn insert(self: *LinearCombination, this_t: *Term) InsertStatus {
        var prev: ?*Term = null;
        var next: ?*Term = self.head;
        if (next == null) {
            self.head = this_t;
            this_t.next = null;
            return .ok;
        }
        while (next) |n| {
            if (n.id != null and this_t.id != null) {
                if (this_t.id.? < n.id.?) {
                    if (prev) |p| {
                        p.next = this_t;
                        this_t.next = n;
                    } else {
                        self.head = this_t;
                        this_t.next = n;
                    }
                    return .ok;
                } else if (this_t.id == n.id) return .err_equal;
            } else if (n.id != null and this_t.id == null) {
                if (n.next == null) {
                    n.next = this_t;
                    this_t.next = null;
                    return .ok;
                }
            } else if (n.id == null and this_t.id != null) {
                if (prev) |p| {
                    p.next = this_t;
                    this_t.next = n;
                } else {
                    self.head = this_t;
                    this_t.next = n;
                }
                return .ok;
            } else if (n.id == null and this_t.id == null) {
                return .err_equal;
            }
            prev = next;
            next = n.next;
            if (next == null) {
                n.next = this_t;
                this_t.next = null;
                return .ok;
            }
        }
        return .ok;
    }
    ///Clones as an allocated linked list.
    pub fn clone(self: LinearCombination, allocator: std.mem.Allocator) !LinearCombination {
        var lc_clone: LinearCombination = .empty_alloc;
        errdefer lc_clone.deinit(allocator);
        var clone_prev: ?*Term = null;
        var next: ?*Term = self.head;
        while (next) |n| {
            const new_t = try allocator.create(Term);
            new_t.id = n.id;
            new_t.v = n.v;
            new_t.next = null;
            if (clone_prev) |cp| {
                cp.next = new_t;
            } else {
                lc_clone.head = new_t;
            }
            clone_prev = new_t;
            next = n.next;
        }
        return lc_clone;
    }
    pub fn div_exact_row(self: *LinearCombination, v: i32) void {
        var next: ?*Term = self.head;
        while (next) |n| {
            n.v = @divExact(n.v, v);
            next = n.next;
        }
    }
    pub fn eq(self: LinearCombination, other: LinearCombination) bool {
        var self_next: ?*const Term = self.head;
        var other_next: ?*const Term = other.head;
        while (self_next != null or other_next != null) {
            const sn = self_next orelse return false;
            const on = other_next orelse return false;
            if (sn.id != on.id or sn.v != on.v)
                return false;
            self_next = sn.next;
            other_next = on.next;
        }
        return true;
    }
    ///Terms with .next in arr is not necessary.
    pub fn eq_array(self: LinearCombination, arr: []const Term) bool {
        var self_next: ?*const Term = self.head;
        var arr_i: usize = 0;
        while (self_next) |sn| {
            if (arr_i == arr.len) return false;
            const elem = arr[arr_i];
            if (sn.id != elem.id or sn.v != elem.v) return false;
            self_next = sn.next;
            arr_i += 1;
        }
        return arr_i == arr.len;
    }
    /// self must have its Term nodes allocated
    /// Any Term with .v == 0 and .id != null is removed.
    pub fn mult_add(
        self: *LinearCombination,
        allocator: std.mem.Allocator,
        other: *const LinearCombination,
        row_m: i32,
    ) !void {
        std.debug.assert(self.alloc_all);
        var self_next: ?*Term = self.head;
        var self_prev: ?*Term = null;
        var other_next: ?*const Term = other.head;
        while (other_next) |on| {
            while (self_next) |sn| {
                //.id for other should be smaller than self, where order is 0, 1, 2, ..., null
                if (sn.id != null and on.id != null) {
                    if (on.id.? <= sn.id.?) break;
                } else if (sn.id == null and on.id == null) {
                    break;
                } else if (sn.id == null and on.id != null) {
                    break;
                }
                self_prev = self_next;
                self_next = sn.next;
            }
            if (self_next != null and self_next.?.id == on.id) {
                self_next.?.v += on.v * row_m;
            } else {
                const new_t = try allocator.create(Term);
                errdefer allocator.destroy(new_t);
                new_t.* = .{ .v = on.v * row_m, .id = on.id, .next = self_next };
                if (self_prev) |sp| {
                    sp.next = new_t;
                } else {
                    self.head = new_t;
                }
                self_prev = new_t;
            }
            other_next = on.next;
        }
        self.remove_zeroes(allocator);
    }
    /// Any non-nullable id with 0 .v is removed.
    pub fn remove_zeroes(self: *LinearCombination, allocator: std.mem.Allocator) void {
        std.debug.assert(self.alloc_all);
        var next: ?*Term = self.head;
        var prev: ?*Term = null;
        while (next) |n| {
            const n_next = n.next;
            if (n.id != null and n.v == 0) {
                if (prev) |p| {
                    p.next = n_next;
                } else {
                    self.head = n_next;
                }
                allocator.destroy(n);
            } else {
                prev = next;
            }
            next = n_next;
        }
    }
    pub fn remove(self: *LinearCombination, allocator: std.mem.Allocator, id: ?u31) void {
        std.debug.assert(self.alloc_all);
        var prev: ?*Term = null;
        var next: ?*Term = self.head;
        while (next) |n| {
            if (n.id == id) {
                if (prev) |p| {
                    p.next = n.next;
                } else {
                    self.head = n.next;
                }
                allocator.destroy(n);
                return;
            }
            prev = next;
            next = n.next;
        }
    }
    /// Order of .id should be strictly increasing numbers and ending in null just once, or just null only.
    pub fn valid_order(self: LinearCombination) bool {
        var next: ?*const Term = self.head;
        const IsValidState = union(enum) {
            start,
            incr: u31,
            null,
        };
        var state: IsValidState = .start;
        while (next) |n| {
            switch (state) {
                .start => {
                    if (n.id) |id| {
                        state = .{ .incr = id };
                    } else {
                        state = .null;
                    }
                },
                .incr => |*last_id| {
                    if (n.id) |id| {
                        if (id <= last_id.*) return false;
                        last_id.* = id;
                    } else state = .null;
                },
                .null => return false, //.null and only one .null should be the last in the LinearCombination.
            }
            next = n.next;
        }
        return state == .null;
    }
    pub fn count(self: LinearCombination) usize {
        var next: ?*const Term = self.head;
        var c: usize = 0;
        while (next) |n| {
            c += 1;
            next = n.next;
        }
        return c;
    }
    pub fn deinit(self: LinearCombination, allocator: std.mem.Allocator) void {
        if (self.alloc_all) {
            var next: ?*const Term = self.head;
            while (next) |n| {
                next = n.next;
                allocator.destroy(n);
            }
        }
    }
};
pub const Term = struct {
    v: i32,
    /// id representing a square in the board
    /// and null id represents the number of mines
    id: ?u31,
    next: ?*Term = null,
};
const t_allocator = std.testing.allocator;
test "LinearCombination.deinit" {
    const t1 = try t_allocator.create(Term);
    errdefer t_allocator.destroy(t1);
    t1.* = .{ .v = 2, .id = 1, .next = null };
    const t2 = try t_allocator.create(Term);
    errdefer t_allocator.destroy(t2);
    t2.* = .{ .v = 3, .id = 2, .next = null };
    const t3 = try t_allocator.create(Term);
    t3.* = .{ .v = 4, .id = null, .next = null };
    t1.next = t2;
    t2.next = t3;
    const lc: LinearCombination = .{ .head = t1, .alloc_all = true };
    defer lc.deinit(t_allocator);
}
test "LinearCombination.valid_order" {
    try std.testing.expect(!(LinearCombination.empty).valid_order());
    var t1: Term = .{ .v = 0, .id = 0, .next = null };
    var t2: Term = .{ .v = 1, .id = 1, .next = null };
    var t3: Term = .{ .v = 2, .id = 2, .next = null };
    var t4: Term = .{ .v = 3, .id = null, .next = null };
    var t5: Term = .{ .v = 4, .id = 1, .next = null };
    t1.next = &t2;
    t2.next = &t3;
    t3.next = &t4;
    try std.testing.expect((LinearCombination{ .head = &t1 }).valid_order());
    t4.next = &t4; //2 null ids should not happen
    try std.testing.expect(!(LinearCombination{ .head = &t1 }).valid_order());
    t3.next = null; //null is expected
    try std.testing.expect(!(LinearCombination{ .head = &t1 }).valid_order());
    t2.next = &t1;
    t1.next = &t4;
    t4.next = null; //decreasing id number
    try std.testing.expect(!(LinearCombination{ .head = &t2 }).valid_order());
    t5.next = &t2;
    t2.next = &t3;
    t3.next = &t4;
    t4.next = null; //same id number
    try std.testing.expect(!(LinearCombination{ .head = &t5 }).valid_order());
}
test "LinearCombination.insert" {
    var lc1: LinearCombination = .empty;
    var t1: Term = .{ .v = 1, .id = null };
    try std.testing.expect(lc1.insert(&t1) == .ok);
    try std.testing.expect(lc1.valid_order());
    var t2: Term = .{ .v = 2, .id = 1 };
    try std.testing.expect(lc1.insert(&t2) == .ok);
    try std.testing.expect(lc1.valid_order());
    var t3: Term = .{ .v = 3, .id = 2 };
    try std.testing.expect(lc1.insert(&t3) == .ok);
    try std.testing.expect(lc1.valid_order());
    var t4: Term = .{ .v = 4, .id = 0 };
    try std.testing.expect(lc1.insert(&t4) == .ok);
    try std.testing.expect(lc1.valid_order());
    var t5: Term = .{ .v = 5, .id = null };
    try std.testing.expect(lc1.insert(&t5) == .err_equal);
    var t6: Term = .{ .v = 6, .id = 0 };
    try std.testing.expect(lc1.insert(&t6) == .err_equal);
    try std.testing.expect(lc1.valid_order());
    try std.testing.expect(lc1.eq_array(&.{
        Term{ .id = 0, .v = 4 },
        Term{ .id = 1, .v = 2 },
        Term{ .id = 2, .v = 3 },
        Term{ .id = null, .v = 1 },
    }));
    var lc2: LinearCombination = .empty;
    var t7: Term = .{ .v = 7, .id = 0 };
    try std.testing.expect(lc2.insert(&t7) == .ok);
    try std.testing.expect(!lc2.valid_order());
    var t8: Term = .{ .v = 8, .id = 2 };
    try std.testing.expect(lc2.insert(&t8) == .ok);
    try std.testing.expect(!lc2.valid_order());
    var t9: Term = .{ .v = 9, .id = 1 };
    try std.testing.expect(lc2.insert(&t9) == .ok);
    try std.testing.expect(!lc2.valid_order());
    var t10: Term = .{ .v = 10, .id = null };
    try std.testing.expect(lc2.insert(&t10) == .ok);
    try std.testing.expect(lc2.valid_order());
    try std.testing.expect(lc2.eq_array(&.{
        Term{ .id = 0, .v = 7 },
        Term{ .id = 1, .v = 9 },
        Term{ .id = 2, .v = 8 },
        Term{ .id = null, .v = 10 },
    }));
}
test "LinearCombination.remove" {
    var lc: LinearCombination = .empty_alloc;
    defer lc.deinit(t_allocator);
    const t1 = try t_allocator.create(Term);
    t1.* = .{ .v = 2, .id = 0 };
    _ = lc.insert(t1);
    const t2 = try t_allocator.create(Term);
    t2.* = .{ .v = 4, .id = 1 };
    _ = lc.insert(t2);
    const t3 = try t_allocator.create(Term);
    t3.* = .{ .v = 6, .id = 2 };
    _ = lc.insert(t3);
    try std.testing.expect(lc.eq_array(&.{
        Term{ .id = 0, .v = 2 },
        Term{ .id = 1, .v = 4 },
        Term{ .id = 2, .v = 6 },
    }));
    lc.remove(t_allocator, 1);
    try std.testing.expect(lc.eq_array(&.{
        Term{ .id = 0, .v = 2 },
        Term{ .id = 2, .v = 6 },
    }));
    lc.remove(t_allocator, 2);
    try std.testing.expect(lc.eq_array(&.{
        Term{ .id = 0, .v = 2 },
    }));
    lc.remove(t_allocator, 0);
    try std.testing.expect(lc.eq_array(&.{}));
}
test "LinearCombination.eq" {
    var lc1: LinearCombination = .empty;
    var t1: Term = .{ .v = 1, .id = 0 };
    _ = lc1.insert(&t1);
    var t2: Term = .{ .v = 2, .id = 1 };
    _ = lc1.insert(&t2);
    var t3: Term = .{ .v = 3, .id = null };
    _ = lc1.insert(&t3);
    var t4: Term = .{ .v = 4, .id = 5 };
    _ = lc1.insert(&t4);
    var t5: Term = .{ .v = 5, .id = 3 };
    _ = lc1.insert(&t5);
    var lc2: LinearCombination = .empty;
    var t6: Term = .{ .v = 5, .id = 3 };
    _ = lc2.insert(&t6);
    var t7: Term = .{ .v = 4, .id = 5 };
    _ = lc2.insert(&t7);
    var t8: Term = .{ .v = 3, .id = null };
    _ = lc2.insert(&t8);
    var t9: Term = .{ .v = 2, .id = 1 };
    _ = lc2.insert(&t9);
    var t10: Term = .{ .v = 1, .id = 0 };
    _ = lc2.insert(&t10);
    try std.testing.expect(lc1.eq(lc2));
    t9.next = null;
    try std.testing.expect(!lc1.eq(lc2));
    t3.next = null;
    try std.testing.expect(!lc1.eq(lc2));
    t2.next = null;
    try std.testing.expect(lc1.eq(lc2));
    t2.v = 10; //.id is equal but .v is not equal
    try std.testing.expect(!lc1.eq(lc2));
    t9 = .{ .v = 10, .id = 2 }; //.v is equal but .id is not equal
    try std.testing.expect(!lc1.eq(lc2));
}

test "LinearCombination.mult_add" {
    var lc1: LinearCombination = .empty_alloc;
    defer lc1.deinit(t_allocator);
    const t1 = try t_allocator.create(Term);
    t1.* = .{ .v = 0, .id = 0 };
    _ = lc1.insert(t1);
    const t2 = try t_allocator.create(Term);
    t2.* = .{ .v = 1, .id = 1 };
    _ = lc1.insert(t2);
    const t3 = try t_allocator.create(Term);
    t3.* = .{ .v = 1, .id = 2 };
    _ = lc1.insert(t3);
    var lc2: LinearCombination = .empty;
    defer lc2.deinit(t_allocator);
    var t4: Term = .{ .v = -2, .id = null };
    _ = lc2.insert(&t4);
    var t5: Term = .{ .v = 1, .id = 2 };
    _ = lc2.insert(&t5);
    try lc1.mult_add(t_allocator, &lc2, -1);
}
test "LinearCombination.clone" {
    var lc1: LinearCombination = .empty;
    var t1: Term = .{ .id = null, .v = 10 };
    var t2: Term = .{ .id = 2, .v = 20 };
    var t3: Term = .{ .id = 4, .v = 30 };
    _ = lc1.insert(&t1);
    _ = lc1.insert(&t2);
    _ = lc1.insert(&t3);
    var lc2: LinearCombination = try lc1.clone(t_allocator);
    defer lc2.deinit(t_allocator);
    try std.testing.expect(lc1.eq(lc2));
}

test "MinesweeperMatrix.rref" {
    var mm: MinesweeperMatrix = .empty;
    defer mm.deinit(t_allocator);
    try mm.append(t_allocator, try .init_minesweeper_row(t_allocator, &.{ 0, 1 }, 1));
    try mm.append(t_allocator, try .init_minesweeper_row(t_allocator, &.{ 0, 1, 2 }, 2));
    try mm.append(t_allocator, try .init_minesweeper_row(t_allocator, &.{ 1, 2, 3 }, 2));
    try mm.append(t_allocator, try .init_minesweeper_row(t_allocator, &.{ 2, 3 }, 1));
}
test "MinesweeperMap.init_parse" {
    var mp_status = MapParser.init_parse("012\n345\n678\nccf\n", t_allocator);
    if (mp_status == .ok) {
        defer mp_status.ok.deinit(t_allocator);
        try std.testing.expectEqualSlices(MsType, mp_status.ok.map.items, &[_]MsType{
            .@"0", .@"1", .@"2", .@"3", .@"4", .@"5", .@"6", .@"7", .@"8", .unknown, .unknown, .flag,
        });
        try std.testing.expectEqual(@as(usize, 3), mp_status.ok.width);
        try std.testing.expectEqual(@as(usize, 4), mp_status.ok.height);
    } else {
        return error.UnexpectedStatus;
    }
}
test "Tilemap.insert" {
    var tm: TileMap = .empty;
    defer tm.deinit(t_allocator);
    try std.testing.expectEqual(@as(usize, 0), try tm.insert(t_allocator, .{ .x = 1, .y = 2 }));
    try std.testing.expectEqual(@as(usize, 0), try tm.insert(t_allocator, .{ .x = 1, .y = 2 })); //Nothing should happen (Duplicate)
    try std.testing.expectEqual(@as(usize, 1), try tm.insert(t_allocator, .{ .x = 3, .y = 4 }));
    try std.testing.expectEqual(tm.get_location(0), TileLocation{ .x = 1, .y = 2 });
    try std.testing.expectEqual(tm.get_id(.{ .x = 3, .y = 4 }), @as(usize, 1));
}
test "MinesweeperMatrix.separate_subsystems" {
    var mp_status = MapParser.init_parse("ccccc\nc121c\nccccc", t_allocator);
    if (mp_status == .ok) {
        defer mp_status.ok.deinit(t_allocator);
        var mm = try mp_status.ok.to_minesweeper_matrix(t_allocator);
        defer mm.deinit(t_allocator);
        std.debug.print("{p}\nSeparating equations to different subsystems\n", .{mm});
        const mms = try mm.separate_subsystems(t_allocator);
        defer {
            for (mms) |*mm_sub| {
                std.debug.print("{p}", .{mm_sub});
                mm_sub.deinit(t_allocator);
            }
            t_allocator.free(mms);
        }
        for (mms) |*mm_sub| {
            const solved = try mm_sub.solve(t_allocator, 0);
            defer solved.deinit(t_allocator);
            std.debug.print("{any}\n", .{solved});
        }
    } else {
        return error.UnexpectedStatus;
    }
}
test "MapParser.as_str" {
    const cmp_str = "012\n345\n678\ncvf\n";
    var mp_status = MapParser.init_parse(cmp_str, t_allocator);
    if (mp_status == .ok) {
        defer mp_status.ok.deinit(t_allocator);
        const output_str = try mp_status.ok.as_str(t_allocator);
        defer t_allocator.free(output_str);
        try std.testing.expectEqualStrings(cmp_str, output_str);
    } else {
        return error.UnexpectedStatus;
    }
}
