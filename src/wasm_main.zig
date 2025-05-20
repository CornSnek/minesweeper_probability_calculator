const std = @import("std");
const wasm_print = @import("wasm_print.zig");
const logger = @import("logger.zig");
const minesweeper = @import("minesweeper.zig");
const shared = @import("shared.zig");
pub const wasm_allocator = std.heap.wasm_allocator;
pub const std_options: std.Options = .{
    .logFn = logger.std_options_impl.logFn,
};
pub const panic = wasm_print.panic;
comptime {
    const jsalloc = @import("wasm_jsalloc.zig");
    std.mem.doNotOptimizeAway(jsalloc.WasmAlloc);
    std.mem.doNotOptimizeAway(jsalloc.WasmFree);
    std.mem.doNotOptimizeAway(jsalloc.WasmFreeAll);
    std.mem.doNotOptimizeAway(jsalloc.WasmListAllocs);
}
var map_parser: ?minesweeper.MapParser = null;
export fn CreateGrid(width: usize, height: usize) void {
    if (map_parser) |*mp| {
        mp.deinit(wasm_allocator);
    }
    const mp_status = minesweeper.MapParser.init(wasm_allocator, width, height);
    if (mp_status == .ok) {
        map_parser = mp_status.ok;
        wasm_print.FlushPrint(false);
    } else {
        std.log.err("Allocator error at CreateGrid\n", .{});
        wasm_print.FlushPrint(false);
    }
}
/// Return -1 if x/y is out of range
export fn QueryTile(x: usize, y: usize) usize {
    if (map_parser) |mp| {
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
    if (map_parser) |*mp| {
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
var calculate_array: shared.CalculateArray = .init_error(.unknown);
var mm_whole: minesweeper.MinesweeperMatrix = .empty;
var mm_subsystems: []minesweeper.MinesweeperMatrix = &.{};
export fn CalculateProbability() [*c]shared.CalculateArray {
    calculate_array.deinit(wasm_allocator);
    for (mm_subsystems) |*mm| mm.deinit(wasm_allocator);
    wasm_allocator.free(mm_subsystems);
    mm_subsystems = &.{};
    mm_whole.deinit(wasm_allocator);
    mm_whole = .empty;
    ClearResults();
    if (map_parser) |mp| error_happened: {
        mm_whole = mp.to_minesweeper_matrix(wasm_allocator) catch |e| {
            calculate_array = switch (e) {
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
            var mm_whole_str = stringify_matrix(wasm_allocator, &mm_whole, true) catch {
                calculate_array = .init_error(.alloc_error);
                break :error_happened;
            };
            defer mm_whole_str.deinit(wasm_allocator);
            AppendResults(mm_whole_str.items.ptr, mm_whole_str.items.len);
            wasm_print.FlushPrint(false);
        }
        mm_subsystems = mm_whole.separate_subsystems(wasm_allocator) catch |e| {
            calculate_array = switch (e) {
                error.OutOfMemory => .init_error(.alloc_error),
                error.NoSolutions => .init_error(.no_solutions),
                else => |e2| v: {
                    std.log.err("{!}\n", .{e2});
                    break :v .init_error(.unknown);
                },
            };
            break :error_happened;
        };
        if (mm_subsystems.len > 1) {
            const sm = "This matrix can be partitioned into the following subsystems:<br><br>";
            AppendResults(sm, sm.len);
            for (mm_subsystems, 0..) |sub_mm, ss_i| {
                var alloc_sm: std.ArrayListUnmanaged(u8) = .empty;
                defer alloc_sm.deinit(wasm_allocator);
                alloc_sm.writer(wasm_allocator).print("Subsystem #{}<br>", .{ss_i}) catch {
                    calculate_array = .init_error(.alloc_error);
                    break :error_happened;
                };
                AppendResults(alloc_sm.items.ptr, alloc_sm.items.len);
                var sub_mm_str = stringify_matrix(wasm_allocator, &sub_mm, true) catch {
                    calculate_array = .init_error(.alloc_error);
                    break :error_happened;
                };
                defer sub_mm_str.deinit(wasm_allocator);
                AppendResults(sub_mm_str.items.ptr, sub_mm_str.items.len);
            }
        }
        const pl_list = wasm_allocator.alloc(shared.Calculate, mm_subsystems.len) catch {
            calculate_array = .init_error(.alloc_error);
            break :error_happened;
        };
        for (pl_list) |*pl|
            pl.* = .init_error(.alloc_error);
        calculate_array = .{
            .status = .ok,
            .ptr = pl_list.ptr,
            .len = pl_list.len,
        };
        if (pl_list.len != 0) {
            const sm = "Solving the following system(s) using RREF and brute forcing 0 or 1 for each \\(x_n\\) free variable<br><br>";
            AppendResults(sm, sm.len);
        }
        for (0..mm_subsystems.len) |i| {
            var alloc_sm: std.ArrayListUnmanaged(u8) = .empty;
            defer alloc_sm.deinit(wasm_allocator);
            alloc_sm.writer(wasm_allocator).print("RREF Subsystem #{}<br>", .{i}) catch {
                calculate_array = .init_error(.alloc_error);
                break :error_happened;
            };
            AppendResults(alloc_sm.items.ptr, alloc_sm.items.len);
            const this_mm = &mm_subsystems[i];
            const pl = this_mm.solve_local_only(wasm_allocator) catch |e| {
                pl_list[i] = switch (e) {
                    error.OverFlag => .init_error(.overflag),
                    error.NoSolutionsFound => .init_error(.no_solutions_subsystem),
                    error.OutOfMemory => .init_error(.alloc_error),
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
                };
                this_mm_str.writer(wasm_allocator).print("Total valid solutions found for this subsystem: {}<br><br>", .{pl.total}) catch {};
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
    return &calculate_array;
}
extern fn ClearResults() void;
extern fn AppendResults([*c]const u8, usize) void;
extern fn FinalizeResults() void;
