const std = @import("std");
const json = @import("json");
const clap = @import("clap");
const fs = std.fs;
const hash_map = std.hash_map;

const Allocator = std.heap.GeneralPurposeAllocator(.{});

const EnvMap = hash_map.StringHashMap([]const u8);

const Command = struct {
    command: []const u8,
    file_input: ?[]const u8 = null,
    inherit_env: bool = false,
    env: ?EnvMap = null,
};

const Config = hash_map.StringHashMap(Command);

fn find_config_file(allocator: std.mem.Allocator) !fs.File {
    var dir = fs.cwd();
    var file: ?fs.File = null;
    while (true) {
        const path = try dir.realpathAlloc(allocator, ".");
        defer allocator.free(path);

        if (dir.openFile("vcr.json", .{}) catch null) |f| {
            file = f;
            break;
        }

        const parent_dir = try dir.openDir("..", .{});
        const parent_path = try parent_dir.realpathAlloc(allocator, ".");
        defer allocator.free(parent_path);

        if (std.mem.eql(u8, path, parent_path)) {
            break;
        }

        dir = parent_dir;
    }

    if (file) |f| {
        return f;
    } else {
        return error.InvalidConfig;
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const deinit_status = gpa.deinit();

        if (deinit_status == .leak) {
            std.debug.print("\n\nAllocator leaked...\n\n", .{});
        }
    }

    const allocator = gpa.allocator();

    const params = comptime clap.parseParamsComptime(
        \\-h, --help Display this help and exit.
        \\<str> The command to run
        \\
    );

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
        .allocator = allocator,
    }) catch |err| {
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0)
        return clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});

    if (res.positionals.len < 1) {
        @panic("You must specify a command to run");
    }

    if (res.positionals.len > 1) {
        @panic("Too many positionals somehow");
    }

    const commandName = res.positionals[0];

    const file = try find_config_file(allocator);
    const result = try json.fromReader(allocator, Config, file.reader());
    defer result.deinit();

    const command = if (result.value.get(commandName)) |cmd| cmd else @panic("Invalid command name");
    std.debug.print("{any}\n", .{command});

    // TODO: run the command and pipe stdio
}
