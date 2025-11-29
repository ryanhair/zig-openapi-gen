const std = @import("std");

pub const Spinner = struct {
    thread: ?std.Thread = null,
    should_stop: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    message: []const u8,
    allocator: std.mem.Allocator,

    const frames = [_][]const u8{ "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" };

    pub fn init(allocator: std.mem.Allocator, message: []const u8) Spinner {
        return .{
            .allocator = allocator,
            .message = message,
        };
    }

    pub fn start(self: *Spinner) !void {
        if (self.thread != null) return;
        self.should_stop.store(false, .release);
        self.thread = try std.Thread.spawn(.{}, run, .{self});
    }

    pub fn stop(self: *Spinner) void {
        if (self.thread) |thread| {
            self.should_stop.store(true, .release);
            thread.join();
            self.thread = null;
            // Clear the spinner line
            std.debug.print("\r\x1b[K", .{});
        }
    }

    fn run(self: *Spinner) void {
        var i: usize = 0;
        while (!self.should_stop.load(.acquire)) {
            std.debug.print("\r{s} {s}", .{ frames[i], self.message });
            std.Thread.sleep(80 * std.time.ns_per_ms);
            i = (i + 1) % frames.len;
        }
    }
};

pub fn printError(comptime fmt: []const u8, args: anytype) void {
    std.debug.print("\x1b[31mError:\x1b[0m " ++ fmt ++ "\n", args);
}

pub fn printSuccess(comptime fmt: []const u8, args: anytype) void {
    std.debug.print("\x1b[32mSuccess:\x1b[0m " ++ fmt ++ "\n", args);
}

pub fn printInfo(comptime fmt: []const u8, args: anytype) void {
    std.debug.print("\x1b[34mInfo:\x1b[0m " ++ fmt ++ "\n", args);
}
