pub const MsType = @import("minesweeper.zig").MsType;
pub const PrintType = enum(i32) { log, warn, err };
pub const CalculateStatus = enum(u8) {
    ok,
    alloc_error,
    overflag,
    no_solutions,
    no_solutions_subsystem,
    cancelled,
    unknown,
    pub fn error_message(self: CalculateStatus) []const u8 {
        return switch (self) {
            .ok => "",
            .alloc_error => "Unable to allocate WASM memory.",
            .overflag => "No solutions were found because a number tile was detected for having too many flags or mines.",
            .no_solutions => "No solutions were found. The configuration of the number tiles is incorrect or impossible.",
            .no_solutions_subsystem => "No solutions were found for this subsystem. The configuration of the number tiles is incorrect or impossible.",
            .cancelled => "Calculation was cancelled.",
            .unknown => "An unexpected error has happened. This error should not exist because the developer have overlooked this error.",
        };
    }
};
pub const TileLocation = @import("minesweeper.zig").TileLocation;
pub const IDToLocationExtern = @import("minesweeper.zig").TileMap.IDToLocationExtern;
pub const LocationCount = @import("minesweeper.zig").MinesweeperMatrix.LocationCount;
pub const MineFrequency = @import("minesweeper.zig").MinesweeperMatrix.MineFrequency;
pub const ProbabilityList = @import("minesweeper.zig").MinesweeperMatrix.ProbabilityList;
pub const Calculate = extern struct {
    tm: IDToLocationExtern,
    pl: ProbabilityList,
    status: CalculateStatus,
    pub fn init_error(status: CalculateStatus) Calculate {
        @import("std").debug.assert(status != .ok);
        return .{ .tm = .empty, .pl = .empty, .status = status };
    }
    pub fn deinit(self: Calculate, allocator: @import("std").mem.Allocator) void {
        if (self.status == .ok) {
            self.pl.deinit(allocator);
        }
    }
};
pub const CalculateArray = extern struct {
    status: CalculateStatus,
    recalculated: bool,
    ptr: [*c]Calculate,
    len: usize,
    pub fn init_error(status: CalculateStatus) CalculateArray {
        return .{ .status = status, .recalculated = false, .len = 0, .ptr = 0 };
    }
    pub fn deinit(self: CalculateArray, allocator: @import("std").mem.Allocator) void {
        if (self.ptr != 0) {
            const self_slice = self.ptr[0..self.len];
            for (self_slice) |c| {
                if (c.status == .ok) {
                    c.pl.deinit(allocator);
                }
            }
            allocator.free(self_slice);
        }
    }
};
pub const TestTypeInfo = @import("print_wasm32_info.zig").TestTypeInfo;
