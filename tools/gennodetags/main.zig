const std = @import("std");

const pg = @cImport({
    @cInclude("c.h");
    @cInclude("utils/palloc.h");
    @cInclude("nodes/nodes.h");
});

const tagsOnly = std.StaticStringMap(void).initComptime([_]struct { []const u8 }{
    // Internal markers
    .{"T_Invalid"},

    // Tags for internal types
    .{"T_AllocSetContext"},
    .{"T_GenerationContext"},
    .{"T_SlabContext"},
    .{"T_WindowObjectData"},
    .{"T_BumpContext"},

    // List types (only tags, all use the `List` type)
    .{"T_IntList"},
    .{"T_OidList"},
    .{"T_XidList"},
});

pub fn main() !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const args = try std.process.argsAlloc(arena);
    if (args.len != 2)
        fatal("wrong number of arguments", .{});

    var out = std.fs.cwd().createFile(args[1], .{}) catch |err| {
        fatal("create file {s}: {}\n", .{ args[1], err });
    };
    defer out.close();

    var write_buf: [4096]u8 = undefined;
    var file_writer = out.writer(&write_buf);
    const w = &file_writer.interface;

    try w.writeAll(
        \\pub const std = @import("std");
        \\
        \\pub const pg = @import("pgzx_pgsys");
        \\
        \\
    );

    // 1. collect all node tags into `node_tags` list using comptime reflection.
    @setEvalBranchQuota(50000);
    var node_tags: std.ArrayList([]const u8) = .{};
    defer node_tags.deinit(arena);
    const pg_mod = @typeInfo(pg).@"struct";
    inline for (pg_mod.decls) |decl| {
        const name = decl.name;
        if (std.mem.startsWith(u8, name, "T_")) {
            node_tags.append(arena, decl.name) catch |err| {
                fatal("build node tags list: {}\n", .{err});
            };
        }
    }

    // 2. Create `Tag enum` with all known node tags.
    try w.writeAll("pub const Tag = enum (pg.NodeTag) {\n");
    for (node_tags.items) |tag| {
        const name = tag[2..];
        try w.print("{s} = pg.{s},\n", .{ name, tag });
    }
    try w.writeAll("};\n\n");

    // 3. Create types -> tags mappings. Only add tags for valid types.
    try w.writeAll("pub const TypeTagTable = .{\n");
    for (node_tags.items) |tag| {
        if (tagsOnly.has(tag))
            continue;

        const typeName = tag[2..];
        try w.writeAll(".{");
        try w.print("pg.{s}, pg.{s}", .{ tag, typeName });
        try w.writeAll("},\n");
    }
    try w.writeAll("};\n");

    try w.writeAll(
        \\pub inline fn findTag(comptime T: type) ?Tag {
        \\    inline for (TypeTagTable) |entry| {
        \\        if (entry[1] == T) {
        \\            return @enumFromInt(entry[0]);
        \\        }
        \\    }
        \\    return null;
        \\}
        \\
        \\pub inline fn findType(comptime tag: Tag) ?type {
        \\    const tag_int: c_int = @intCast(@intFromEnum(tag));
        \\    inline for (TypeTagTable) |entry| {
        \\        if (entry[0] == tag_int) {
        \\            return entry[1];
        \\        }
        \\    }
        \\    return null;
        \\}
    );

    try w.flush();
    return std.process.cleanExit();
}

fn fatal(comptime format: []const u8, args: anytype) noreturn {
    std.debug.print(format, args);
    std.process.exit(1);
}
