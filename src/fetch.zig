const std = @import("std");
const ui = @import("ui.zig");

pub fn fetchSpec(allocator: std.mem.Allocator, url: []const u8) ![]const u8 {
    var spinner = ui.Spinner.init(allocator, "Fetching spec...");
    try spinner.start();
    defer spinner.stop();

    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    const uri = try std.Uri.parse(url);

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
}
