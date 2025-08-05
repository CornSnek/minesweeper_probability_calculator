const std = @import("std");
const wasm_print = @import("wasm_print.zig");
const logger = @import("logger.zig");
const minesweeper = @import("minesweeper.zig");
const shared = @import("shared.zig");
pub const wasm_allocator = std.heap.wasm_allocator;
pub const std_options: std.Options = .{
    .logFn = logger.std_options_impl.logFn,
};
pub const panic = std.debug.FullPanic(wasm_print.panic);
comptime {
    const jsalloc = @import("wasm_jsalloc.zig");
    std.mem.doNotOptimizeAway(jsalloc.WasmAlloc);
    std.mem.doNotOptimizeAway(jsalloc.WasmFree);
    std.mem.doNotOptimizeAway(jsalloc.WasmFreeAll);
    std.mem.doNotOptimizeAway(jsalloc.WasmListAllocs);
    const rng = @import("rng.zig");
    std.mem.doNotOptimizeAway(rng.InitRNGSeed);
    std.mem.doNotOptimizeAway(rng.MinesweeperInitEmpty);
    std.mem.doNotOptimizeAway(rng.ParsedWidth);
    std.mem.doNotOptimizeAway(rng.ParsedHeight);
    std.mem.doNotOptimizeAway(rng.ParsedNumMines);
}
pub const CalculatedMap = struct {
    map_parser: ?minesweeper.MapParser,
    calculate_array: shared.CalculateArray,
    mm_whole: minesweeper.MinesweeperMatrix,
    mm_subsystems: []minesweeper.MinesweeperMatrix,
    last_calculate_str: ?[]u8 = null,
    pub const empty: CalculatedMap = .{
        .map_parser = null,
        .calculate_array = .init_error(.unknown),
        .mm_whole = .empty,
        .mm_subsystems = &.{},
        .last_calculate_str = null,
    };
    pub fn is_probability_calculated(self: CalculatedMap) bool {
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
            other.*.map_parser = mp_clone;
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
) !std.ArrayListUnmanaged(u8) {
    var results: std.ArrayListUnmanaged(u8) = .empty;
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
                try results.writer(allocator).print("x_{{{?}}}", .{n.id});
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
                try results.writer(allocator).print("x_{{{?}}}", .{n.id});
            }
            next = n.next;
        }
    }
    if (show_ids) {
        if (mm.tm.idtol.items.len != 0)
            try results.writer(allocator).writeAll("Where \\(");
        for (mm.tm.idtol.items, 0..) |loc, id| {
            try results.writer(allocator).print("x_{{{?}}}=\\langle{},{}\\rangle,\\,", .{ id, loc.x, loc.y });
        }
        if (mm.tm.idtol.items.len != 0) {
            try results.writer(allocator).writeAll("\\)<br>");
            try results.writer(allocator).writeAll("<br>");
        }
    }
    return results;
}
export fn CalculateProbability() [*c]shared.CalculateArray {
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
                    std.log.err("{!}\n", .{e2});
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
                    std.log.err("{!}\n", .{e2});
                    break :v .init_error(.unknown);
                },
            };
            break :error_happened;
        };
        if (cm.mm_subsystems.len > 1) {
            const sm = "This matrix can be partitioned into the following subsystems:<br><br>";
            AppendResults(sm, sm.len);
            for (cm.mm_subsystems, 0..) |sub_mm, ss_i| {
                var alloc_sm: std.ArrayListUnmanaged(u8) = .empty;
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
            var alloc_sm: std.ArrayListUnmanaged(u8) = .empty;
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
            var this_mm_str: std.ArrayListUnmanaged(u8) = stringify_matrix(wasm_allocator, this_mm, false) catch .empty;
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
pub extern fn ClearResults() void;
pub extern fn AppendResults([*c]const u8, usize) void;
pub extern fn FinalizeResults() void;
pub extern fn SetSubsystemNumber(usize) void;
pub extern fn SetTimeoutProgress(usize, f32) void;
pub export var CalculateStatus: bool = false;
pub export var CancelCalculation: bool = false;
