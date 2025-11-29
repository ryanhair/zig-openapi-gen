const std = @import("std");
const parser = @import("parser.zig");
const generator = @import("generator.zig");
const cli = @import("cli.zig");
const scaffold = @import("scaffold.zig");
const ui = @import("ui.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const command = cli.parseArgs(allocator) catch |err| {
        ui.printError("Failed to parse arguments: {}", .{err});
        return err;
    };

    switch (command) {
        .generate => |args| {
            handleGenerate(allocator, args.input_spec, args.output_dir) catch |err| {
                ui.printError("Generation failed: {}", .{err});
                return err;
            };
        },
        .init => |args| {
            scaffold.generateProject(allocator, args.spec_source, args.output_dir, args.skip_ci) catch |err| {
                ui.printError("Initialization failed: {}", .{err});
                return err;
            };
        },
        .ci_init => |args| {
            scaffold.generateCI(args.output_dir) catch |err| {
                ui.printError("CI generation failed: {}", .{err});
                return err;
            };
        },
        .update => {
            scaffold.updateProject(allocator) catch |err| {
                ui.printError("Update failed: {}", .{err});
                return err;
            };
        },
        .help => {
            cli.printUsage();
        },
    }
}

fn handleGenerate(allocator: std.mem.Allocator, input_path: []const u8, output_dir_path: []const u8) !void {
    const file = try std.fs.cwd().openFile(input_path, .{});
    defer file.close();

    const file_size = (try file.stat()).size;
    const buffer = try allocator.alloc(u8, file_size);
    defer allocator.free(buffer);

    _ = try file.readAll(buffer);

    const parsed = try parser.parse(allocator, buffer);
    defer parsed.deinit();

    try std.fs.cwd().makePath(output_dir_path);
    var output_dir = try std.fs.cwd().openDir(output_dir_path, .{});
    defer output_dir.close();

    try generator.generate(allocator, parsed.value, output_dir);
    std.debug.print("Successfully generated code in {s}\n", .{output_dir_path});
}
