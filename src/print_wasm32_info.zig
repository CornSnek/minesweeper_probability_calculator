const shared = @import("shared.zig");
const std = @import("std");
const QueryErrorStatus = enum(usize) {
    struct_id_not_struct = std.math.maxInt(usize),
    struct_id_out_of_range = std.math.maxInt(usize) - 1,
    field_id_out_of_range = std.math.maxInt(usize) - 2,
    invalid_info_type = std.math.maxInt(usize) - 3,
    fn value(self: QueryErrorStatus) usize {
        return @intFromEnum(self);
    }
};
///Query struct/field/info_type based on the order of the structs in 'shared.zig'
export fn Query(
    struct_id: usize,
    field_id: usize,
    info_type: usize,
) usize {
    inline for (@typeInfo(shared).@"struct".decls, 0..) |d, i| {
        if (i == struct_id) {
            const field_obj = @field(shared, d.name);
            const field_info = @typeInfo(field_obj);
            if (field_info == .@"struct") {
                inline for (field_info.@"struct".fields, 0..) |f, j| {
                    if (j == field_id) {
                        return switch (info_type) {
                            0 => @sizeOf(f.type),
                            1 => @offsetOf(field_obj, f.name),
                            2 => @alignOf(f.type),
                            3 => @sizeOf(field_obj),
                            4 => @alignOf(field_obj),
                            else => QueryErrorStatus.invalid_info_type.value(),
                        };
                    }
                } else return QueryErrorStatus.field_id_out_of_range.value();
            } else return QueryErrorStatus.struct_id_not_struct.value();
        }
    } else return QueryErrorStatus.struct_id_out_of_range.value();
}

pub const TestTypeInfo = extern struct {
    ///(size, alignment) = (1, 1)
    a_u8: u8, //floats, and signed integers generally have the same size/alignment (E.g. i8 is the same as u8, and f32 is the same as u32)
    ///(size, alignment) = (2, 2)
    a_u16: u16,
    ///(size, alignment) = (4, 4)
    a_u32: u32,
    ///(size, alignment) = (8, 8)
    a_u64: u64,
    ///(size, alignment) = (16, x), where alignment is 16 for 'extern struct', but 8 for 'struct'
    a_u128: u128,
    ///(size, alignment) = (4, 4)
    a_usize: usize,
    ///(size, alignment) = (1, 1)
    a_bool: bool,
    ///(size, alignment) = (0, 1)
    a_void: void,
    ///(size, alignment) = (4, 4)
    a_ptr: [*c]bool, //Generally any pointer
};
