const std = @import("std");
fn EnumsToJSClass(EnumClass: anytype, comptime export_name: []const u8) []const u8 {
    if (@typeInfo(EnumClass) != .@"enum") @compileError(@typeName(EnumClass) ++ " must be an enum type.");
    comptime var export_str: []const u8 = &.{};
    export_str = export_str ++ std.fmt.comptimePrint("//Exported Zig enums '{s}' to class name '{s}'\n", .{ @typeName(EnumClass), export_name });
    export_str = export_str ++ "export class " ++ export_name ++ " {\n";
    const fields = std.meta.fields(EnumClass);
    inline for (fields) |field| {
        switch (field.name[0]) {
            '0'...'9' => export_str = export_str ++ std.fmt.comptimePrint("\tstatic get \"{s}\"() {{ return {}; }}\n", .{ field.name, field.value }),
            else => export_str = export_str ++ std.fmt.comptimePrint("\tstatic get {s}() {{ return {}; }}\n", .{ field.name, field.value }),
        }
    }
    export_str = export_str ++ std.fmt.comptimePrint("\tstatic get $$length() {{ return {}; }}\n", .{fields.len});
    export_str = export_str ++ "\tstatic get $$names() { return Array.from([";
    inline for (fields) |field|
        export_str = export_str ++ std.fmt.comptimePrint(" \"{s}\",", .{field.name});
    export_str = export_str ++ " ]); }\n";
    inline for (@typeInfo(EnumClass).@"enum".decls) |decl| {
        const DeclType = @TypeOf(@field(EnumClass, decl.name));
        if (@typeInfo(DeclType) == .@"fn") {
            const FnInfo = @typeInfo(DeclType).@"fn";
            if (FnInfo.params.len == 1 and FnInfo.params[0].type == EnumClass) {
                //Return arrays of enums for strings, boolean, numbers
                if (FnInfo.return_type == []const u8) {
                    export_str = export_str ++ "\tstatic get $" ++ decl.name ++ "() { return Array.from([";
                    inline for (fields) |field|
                        export_str = export_str ++ std.fmt.comptimePrint(" \"{s}\",", .{@field(EnumClass, decl.name)(@enumFromInt(field.value))});
                    export_str = export_str ++ " ]); }\n";
                } else if (FnInfo.return_type == bool) {
                    export_str = export_str ++ "\tstatic get $" ++ decl.name ++ "() { return Array.from([";
                    inline for (fields) |field|
                        export_str = export_str ++ std.fmt.comptimePrint(" {},", .{@field(EnumClass, decl.name)(@enumFromInt(field.value))});
                    export_str = export_str ++ " ]); }\n";
                } else if (@typeInfo(FnInfo.return_type.?) == .int) {
                    export_str = export_str ++ "\tstatic get $" ++ decl.name ++ "() { return Array.from([";
                    inline for (fields) |field|
                        export_str = export_str ++ std.fmt.comptimePrint(" {},", .{@field(EnumClass, decl.name)(@enumFromInt(field.value))});
                    export_str = export_str ++ " ]); }\n";
                } else if (@typeInfo(FnInfo.return_type.?) == .optional) {
                    if (@typeInfo(@typeInfo(FnInfo.return_type.?).optional.child) == .int) {
                        export_str = export_str ++ "\tstatic get $" ++ decl.name ++ "() { return Array.from([";
                        inline for (fields) |field|
                            export_str = export_str ++ std.fmt.comptimePrint(" {?},", .{@field(EnumClass, decl.name)(@enumFromInt(field.value))});
                        export_str = export_str ++ " ]); }\n";
                    }
                }
            }
        }
    }
    export_str = export_str ++ "};\n\n";
    return export_str;
}
const SizeAlignment = struct {
    size: usize,
    alignment: usize,
};
///This assumes no types with custom alignment using align()
fn wasm32_size_alignment_basic(comptime T: type) ?SizeAlignment {
    return switch (T) {
        void => .{ .size = 0, .alignment = 1 },
        u8, i8, bool => .{ .size = 1, .alignment = 1 },
        u16, i16, f16 => .{ .size = 2, .alignment = 2 },
        u32, i32, f32, usize, isize => .{ .size = 4, .alignment = 4 },
        u64, i64, f64 => .{ .size = 8, .alignment = 8 },
        //128 for 'extern struct' has alignment 16 and not 8
        u128, i128, f128 => .{ .size = 16, .alignment = 16 },
        inline else => null,
    };
}
fn pad_offset(offset_and_size: usize, alignment: usize) usize {
    return (offset_and_size + alignment - 1) & ~(alignment - 1);
}
///Get alignment for basic and complex/nested types
///This assumes no types with custom alignment using align()
fn wasm32_size_alignment(comptime T: type) ?SizeAlignment {
    if (wasm32_size_alignment_basic(T)) |sa| {
        return sa;
    } else {
        const StructClassTypeInfo = @typeInfo(T);
        switch (StructClassTypeInfo) {
            .@"struct" => {
                if (StructClassTypeInfo.@"struct".layout != .@"extern")
                    @compileError(@typeName(T) ++ " must be an extern struct type.");
                var offset: usize = 0;
                var biggest_align: usize = 0;
                inline for (StructClassTypeInfo.@"struct".fields) |field| {
                    const sa = wasm32_size_alignment(field.type) orelse return null;
                    //Align offset given previous size added.
                    offset = pad_offset(offset, sa.alignment);
                    biggest_align = @max(biggest_align, sa.alignment);
                    offset += sa.size;
                }
                //offset becomes new size of struct
                offset = pad_offset(offset, biggest_align);
                return .{ .size = offset, .alignment = biggest_align };
            },
            .array => {
                const StructArray = StructClassTypeInfo.array;
                const sa = wasm32_size_alignment(StructArray.child) orelse return null;
                return .{ .size = sa.size * StructArray.len, .alignment = sa.alignment };
            },
            .pointer => return .{ .size = 4, .alignment = 4 },
            .@"enum" => return wasm32_size_alignment(StructClassTypeInfo.@"enum".tag_type),
            else => return null,
        }
    }
}
fn StructToOffsetSizeInfo(StructClass: anytype, comptime export_name: []const u8) []const u8 {
    const StructClassTypeInfo = @typeInfo(StructClass);
    if (StructClassTypeInfo != .@"struct") @compileError(@typeName(StructClass) ++ " must be an struct type.");
    comptime var export_str: []const u8 = &.{};
    export_str = export_str ++ std.fmt.comptimePrint("//Exported Zig struct '{s}' to class name '{s}'\n", .{
        @typeName(StructClass),
        export_name,
    });
    export_str = export_str ++ "export class " ++ export_name ++ " {\n";
    var offset: usize = 0;
    inline for (StructClassTypeInfo.@"struct".fields) |field| {
        const sa = wasm32_size_alignment(field.type);
        if (sa == null) @compileError("Type " ++ @typeName(field.type) ++ "is not implemented for field " ++ field.name);
        //Align offset given previous size added.
        offset = pad_offset(offset, sa.?.alignment);
        export_str = export_str ++ std.fmt.comptimePrint("\tstatic get {s}() /*Type '{s}'*/ {{ return {{ offset:{}, size:{}, align:{} }}; }}\n", .{
            field.name,
            @typeName(field.type),
            offset,
            sa.?.size,
            sa.?.alignment,
        });
        offset += sa.?.size;
    }
    const sa_whole = wasm32_size_alignment(StructClass) orelse @compileError("Unexpected error");
    export_str = export_str ++ std.fmt.comptimePrint("\tstatic get $size() {{ return {}; }}\n\tstatic get $align() {{ return {}; }}\n", .{ sa_whole.size, sa_whole.alignment });
    export_str = export_str ++ "};\n\n";
    return export_str;
}
const www_root = "www";
const program_name = "minesweeper_calculator";
pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const exe = b.addExecutable(.{
        .name = program_name,
        .root_module = exe_mod,
    });
    b.installArtifact(exe);
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);

    const install_website = b.addInstallDirectory(.{
        .source_dir = b.path(www_root),
        .install_dir = .bin,
        .install_subdir = www_root,
    });
    const install_website_run_step = b.step("website", "Copies website files to bin");
    b.getInstallStep().dependOn(&install_website.step);
    install_website_run_step.dependOn(&install_website.step);

    const wasm_exe = b.addExecutable(.{
        .name = program_name,
        .root_source_file = b.path("src/wasm_main.zig"),
        .target = b.resolveTargetQuery(.{
            .cpu_arch = .wasm32,
            .os_tag = .freestanding,
        }),
        .optimize = optimize,
    });
    wasm_exe.entry = .disabled;
    wasm_exe.rdynamic = true;
    wasm_exe.root_module.export_symbol_names = &.{
        "WasmListAllocs",
        "WasmAlloc",
        "WasmFree",
        "WasmFreeAll",
        "FlushPrint",
        "PrintBufferMax",
        "CreateGrid",
        "QueryTile",
        "SetTile",
        "CalculateProbability",
    };
    const install_wasm = b.addInstallArtifact(wasm_exe, .{
        .dest_sub_path = try std.fmt.allocPrint(b.allocator, "{s}/{s}.wasm", .{ www_root, program_name }),
    });

    comptime var write_export_enums_str: []const u8 = "//This file is built using 'build.zig' for javascript to interact with the variables referenced in 'src/shared.zig'\n\n";
    inline for (comptime @typeInfo(@import("src/shared.zig")).@"struct".decls) |d| {
        const field_obj = @field(@import("src/shared.zig"), d.name);
        const field_obj_type = @typeInfo(field_obj);
        if (field_obj_type == .@"enum") {
            write_export_enums_str = write_export_enums_str ++ comptime EnumsToJSClass(
                field_obj,
                d.name,
            );
        }
        if (field_obj_type == .@"struct") {
            if (field_obj_type.@"struct".layout == .@"extern") {
                write_export_enums_str = write_export_enums_str ++ comptime StructToOffsetSizeInfo(
                    field_obj,
                    d.name,
                );
            }
        }
    }
    const write_export_file = b.addWriteFile(
        "wasm_to_js.js",
        write_export_enums_str,
    );
    write_export_file.step.dependOn(&install_website.step);
    const add_export_file = b.addInstallDirectory(.{
        .source_dir = write_export_file.getDirectory(),
        .install_dir = .bin,
        .install_subdir = www_root,
    });
    add_export_file.step.dependOn(&write_export_file.step);
    const export_file_step = b.step("export", "Build wasm_to_js.js file for javascript to interact with shared structs built in the zig wasm file");
    export_file_step.dependOn(&add_export_file.step);

    const wasm_step = b.step("wasm", "Build wasm binaries and copies files to bin.");
    wasm_step.dependOn(&install_wasm.step);
    install_wasm.step.dependOn(&add_export_file.step);
    install_wasm.step.dependOn(&install_website.step);

    const print_shared_wasm_info_exe = b.addExecutable(.{
        .name = "print_shared_wasm_info",
        .root_source_file = b.path("src/print_wasm32_info.zig"),
        .target = b.resolveTargetQuery(.{
            .cpu_arch = .wasm32,
            .os_tag = .freestanding,
        }),
        .optimize = .ReleaseSmall,
    });
    print_shared_wasm_info_exe.entry = .disabled;
    print_shared_wasm_info_exe.rdynamic = true;
    print_shared_wasm_info_exe.root_module.export_symbol_names = &.{"Query"};
    const add_print_shared_wasm_info = b.addInstallArtifact(print_shared_wasm_info_exe, .{});
    const print_shared_wasm_info_step = b.step("print", "Get size, offset, alignment variable information of shared structs and types.");
    print_shared_wasm_info_step.dependOn(&add_print_shared_wasm_info.step);
    add_print_shared_wasm_info.step.dependOn(&print_shared_wasm_info_exe.step);

    const run_website_step = b.step("server", "Initializes the wasm step, and runs python http.server");
    const python_http = b.addSystemCommand(&.{ "python", "test_website.py" });
    run_website_step.dependOn(&python_http.step);
    python_http.step.dependOn(&install_wasm.step);
}
