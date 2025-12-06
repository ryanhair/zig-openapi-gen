const std = @import("std");

// Mock Client
const Client = struct {
    base_url: []const u8,

    pub fn resource(self: *const Client, comptime T: type) ResourceClient(T) {
        return ResourceClient(T){ .client = self };
    }
};

// Generic Resource Client
fn ResourceClient(comptime T: type) type {
    if (!@hasDecl(T, "api_metadata")) {
        @compileError("Type " ++ @typeName(T) ++ " must have 'api_metadata' decl to be used as a resource.");
    }
    const metadata = T.api_metadata;

    return struct {
        client: *const Client,

        pub fn list(self: @This()) ![]const T {
            std.debug.print("Listing {s} from {s}{s}\n", .{ @typeName(T), self.client.base_url, metadata.path });
            return &[_]T{};
        }

        pub fn get(self: @This(), name: []const u8) !T {
            std.debug.print("Getting {s} named {s} from {s}{s}/{s}\n", .{ @typeName(T), name, self.client.base_url, metadata.path, name });
            return undefined;
        }
    };
}

// User defined type (e.g. generated or custom)
const Pod = struct {
    name: []const u8,

    pub const api_metadata = .{
        .path = "/api/v1/pods",
    };
};

const MyCRD = struct {
    spec: []const u8,

    pub const api_metadata = .{
        .path = "/apis/my.group/v1/mycrds",
    };
};

pub fn main() !void {
    const client = Client{ .base_url = "https://k8s.example.com" };

    const pods = client.resource(Pod);
    _ = try pods.list();
    _ = try pods.get("my-pod");

    const crds = client.resource(MyCRD);
    _ = try crds.list();
}
