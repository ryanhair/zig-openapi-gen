const std = @import("std");

pub const Command = union(enum) {
    generate: struct {
        input_spec: []const u8,
        output_dir: []const u8,
    },
    init: struct {
        spec_source: []const u8,
        output_dir: []const u8,
        skip_ci: bool,
    },
    ci_init: struct {
        output_dir: []const u8,
    },
    help: void,
};

pub fn parseArgs(allocator: std.mem.Allocator) !Command {
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.skip(); // Skip executable name

    const cmd_str = args.next() orelse return .help;

    if (std.mem.eql(u8, cmd_str, "generate")) {
        const input_spec = args.next() orelse {
            std.debug.print("Error: Missing input spec file\n", .{});
            return .help;
        };
        const output_dir = args.next() orelse {
            std.debug.print("Error: Missing output directory\n", .{});
            return .help;
        };
        return Command{ .generate = .{ .input_spec = input_spec, .output_dir = output_dir } };
    } else if (std.mem.eql(u8, cmd_str, "init")) {
        const spec_source = args.next() orelse {
            std.debug.print("Error: Missing spec source (URL or file)\n", .{});
            return .help;
        };
        const output_dir = args.next() orelse {
            std.debug.print("Error: Missing output directory\n", .{});
            return .help;
        };

        var skip_ci = false;
        if (args.next()) |arg| {
            if (std.mem.eql(u8, arg, "--skip-ci")) {
                skip_ci = true;
            }
        }

        return Command{ .init = .{ .spec_source = spec_source, .output_dir = output_dir, .skip_ci = skip_ci } };
    } else if (std.mem.eql(u8, cmd_str, "ci-init")) {
        const output_dir = args.next() orelse {
            std.debug.print("Error: Missing output directory\n", .{});
            return .help;
        };
        return Command{ .ci_init = .{ .output_dir = output_dir } };
    } else if (std.mem.eql(u8, cmd_str, "help") or std.mem.eql(u8, cmd_str, "--help") or std.mem.eql(u8, cmd_str, "-h")) {
        return .help;
    } else {
        std.debug.print("Error: Unknown command '{s}'\n", .{cmd_str});
        return .help;
    }
}

pub fn printUsage() void {
    std.debug.print(
        \\Usage: openapi-gen <command> [args]
        \\
        \\Commands:
        \\  generate <input_spec> <output_dir>   Generate Zig client code from OpenAPI spec
        \\  init <spec_source> <output_dir>      Initialize a new Zig project with generated client
        \\    --skip-ci                          Skip generation of GitHub Actions CI workflow
        \\  ci-init <output_dir>                 Generate GitHub Actions CI workflow
        \\  help                                 Show this help message
        \\
    , .{});
}
