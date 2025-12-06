# Proposal: UX Enhancements & Extensibility Patterns

This proposal builds upon `crd-proposal.md` to further enhance the Developer Experience (DevX) using Zig's `comptime` capabilities.

## 1. The "Ad-Hoc" Resource Pattern
While `ExtensionClient` (from `crd-proposal.md`) is excellent for structured, bundled extensions, users often need to quickly interact with a resource without setting up a full configuration.

**Proposed API:**
Add a generic `resource(comptime T: type)` method to the base `Client`.

```zig
// User defines a resource (or imports it)
const MyCRD = struct {
    spec: Json,
    // Minimal metadata required
    pub const api_metadata = .{
        .path = "/apis/my.group/v1/mycrds",
        .kind = "MyCRD",
    };
};

// Usage
const my_crds = client.resource(MyCRD);
const items = try my_crds.list(.{ .limit = 10 });
```

**Implementation:**
-   `resource(T)` returns a `ResourceClient(T)` struct at compile time.
-   `ResourceClient(T)` generates methods (`get`, `list`, `watch`, `create`, `delete`) based on the capabilities of `T` (or defaults to all).

## 2. Comptime Path Validation
To prevent runtime errors from malformed paths or missing parameters, we can validate path parameters at compile time.

**Problem:**
```zig
// Runtime error: "id" missing
client.get("/users/{id}", .{ .name = "foo" });
```

**Solution:**
Use `comptime` string parsing to verify arguments.

```zig
// In Client.zig
pub fn get(self: *Client, comptime path: []const u8, args: anytype) !Json {
    comptime validatePathArgs(path, @TypeOf(args));
    // ... runtime logic ...
}

fn validatePathArgs(comptime path: []const u8, comptime Args: type) void {
    // Parse "{id}" from path
    // Check if Args has field "id"
    // Compile error if missing
}
```

## 3. Typed Builder API
For complex operations (like `list` with many filters), a fluent builder API improves readability and discoverability.

**Proposed API:**
```zig
const pods = client.resource(Pod);

const list = try pods.list()
    .namespace("default")
    .labelSelector("app=nginx")
    .limit(10)
    .fetch();
```

**Implementation:**
-   `list()` returns a `ListRequest(T)` struct.
-   `ListRequest(T)` has methods for standard query parameters.
-   `fetch()` executes the request.

## 4. Integration with `ExtensionClient`
The `ExtensionClient` from `crd-proposal.md` can be implemented *on top* of the `resource(T)` pattern.

```zig
pub fn ExtensionClient(comptime config: Config) type {
    return struct {
        base: Client,
        
        // Generated fields for groups
        pub const holon = struct {
            pub const platform = struct {
                // ...
                pub fn service(self: *Self) ResourceClient(Service) {
                    return self.base.resource(Service);
                }
            };
        };
    };
}
```

## Summary of Recommendations
1.  **Adopt the `resource(T)` pattern** as the fundamental building block for extensibility.
2.  **Implement `ExtensionClient`** as a high-level wrapper for organizing resources.
3.  **Add Comptime Path Validation** to all generic request methods.
4.  **Use Builder Pattern** for complex requests (List/Watch).
