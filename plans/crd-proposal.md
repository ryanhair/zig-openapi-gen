# Feature Specification: CRD Support for zig-openapi-gen

## Overview
This document outlines the plan to add first-class support for Kubernetes Custom Resource Definitions (CRDs) to `zig-openapi-gen`. The goal is to provide a type-safe, developer-friendly experience that leverages Zig's `comptime` capabilities and build system.

## 1. Foundation: Generic Watch
**Requirement**: The generated `Client` must support watching arbitrary resources.

### Implementation
Add a static method to the generated `Client` struct:
```zig
pub fn watch(self: *Client, comptime T: type, path: []const u8, options: anytype) !WatchStream(T)
```
- **Functionality**: Handles URL construction, query parameters, and streaming response parsing.
- **Status**: Prototyped and verified in `holon-operator`.

## 2. Core Feature: Comptime Extension API
**Requirement**: Users must be able to extend the client with their own types without regenerating the base library.

### User API
Users define an extension config and create a specialized client type at comptime.

```zig
const k8s = @import("k8s");
const MyCRDs = @import("my_crds.zig"); // User-defined structs

// Define extensions
const extensions = .{
    .{
        .group = "holon.platform",
        .version = "v1alpha1",
        .resources = .{
            .{ .kind = "Service", .type = MyCRDs.Service, .plural = "services" },
        },
    },
};

// Create extended client type
const Client = k8s.ExtensionClient(extensions);

pub fn main() !void {
    var client = try Client.init(allocator, ...);
    
    // Type-safe access!
    var stream = try client.holon.platform.v1alpha1.watchService(.{});
}
```

### Implementation
The generator must emit the `ExtensionClient` function, which returns a wrapper struct that:
1.  Embeds the base `Client`.
2.  Generates nested namespaces (Group -> Version) based on the config.
3.  Generates typed methods (`watchService`, `listService`) that call the base `watch`/`fetch` methods.

## 3. Automation: Build-Time CRD Generation
**Requirement**: Users should be able to generate Zig structs directly from CRD YAML files to ensure a "Single Source of Truth".

### Workflow
1.  **build.zig**:
    ```zig
    const k8s_gen = b.dependency("zig_openapi_gen", ...);
    
    // Generate Zig module from YAML
    const crds_mod = k8s_gen.builder.generateCrds(b, .{
        .manifests = &.{"k8s/crd.yaml"},
    });
    
    exe.root_module.addImport("crds", crds_mod);
    ```

2.  **User Code**:
    ```zig
    const crds = @import("crds");
    // crds.config and crds.types are auto-generated!
    const Client = k8s.ExtensionClient(crds.config);
    ```

### Implementation
`zig-openapi-gen` needs a new build step/command that:
1.  Parses the CRD YAML.
2.  Extracts the OpenAPI schema from `spec.versions[].schema`.
3.  Generates a Zig file containing:
    - The `config` struct (metadata).
    - The `types` (struct definitions matching the schema).

## Summary
This hybrid approach offers the best of both worlds:
- **Flexibility**: `ExtensionClient` allows manual extension for simple cases or custom logic.
- **Automation**: The build helper automates the tedious task of keeping Zig structs in sync with YAML.
