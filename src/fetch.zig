const std = @import("std");
const ui = @import("ui.zig");

pub fn fetchSpec(allocator: std.mem.Allocator, source: []const u8) ![]const u8 {
    if (std.mem.startsWith(u8, source, "http://") or std.mem.startsWith(u8, source, "https://")) {
        var spinner = ui.Spinner.init(allocator, "Fetching spec...");
        try spinner.start();
        defer spinner.stop();

        var client = std.http.Client{ .allocator = allocator };
        defer client.deinit();

        const uri = try std.Uri.parse(source);

        var allocating_writer = std.io.Writer.Allocating.init(allocator);
        defer allocating_writer.deinit();

        const result = try client.fetch(.{
            .location = .{ .uri = uri },
            .method = .GET,
            .response_writer = &allocating_writer.writer,
        });

        if (result.status != .ok) {
            return error.RequestFailed;
        }

        // Optional logging
        std.debug.print("Fetched {d} bytes. Status: {any}\n", .{ allocating_writer.written().len, result.status });

        return try allocating_writer.toOwnedSlice();
    } else {
        ui.printInfo("Reading spec from file: {s}", .{source});
        const file = try std.fs.cwd().openFile(source, .{});
        defer file.close();
        return try file.readToEndAlloc(allocator, 1024 * 1024 * 10);
    }
}
