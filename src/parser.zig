const std = @import("std");

pub fn parse(allocator: std.mem.Allocator, source: []const u8) !std.json.Parsed(std.json.Value) {
    return std.json.parseFromSlice(std.json.Value, allocator, source, .{ .ignore_unknown_fields = true });
}
