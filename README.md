# Zig OpenAPI Generator

A robust OpenAPI 3.0/Swagger 2.0 client generator for Zig.

## Features

*   **Full OpenAPI Support**: Handles Paths, Operations, Parameters (Path, Query, Header, Cookie), and Request Bodies.
*   **Rich Response Types**: Generates tagged unions for responses, including parsed bodies and headers.
*   **Advanced Types**: Supports `oneOf`, `anyOf`, `allOf`, Enums, and recursive types.
*   **Kubernetes Support**: Optimized for large specifications like the Kubernetes API.
*   **Authentication**: Supports API Key, Bearer Token, and other security schemes.
*   **Validation**: Generates runtime validation checks for constraints (minLength, maximum, etc.).
*   **Multi-File Output**: Organizes generated code into a clean directory structure.


## Installation

### Automatic Install (Linux/macOS)
```bash
curl -sSL https://raw.githubusercontent.com/ryanhair/zig-openapi-gen/main/scripts/install.sh | bash
```

### Manual Install
Download the latest release for your platform from the [Releases page](https://github.com/ryanhair/zig-openapi-gen/releases).

## Usage

### Initialize a new project
Initialize a new Zig project with a generated client from an OpenAPI spec (URL or file).

```bash
openapi-gen init https://petstore.swagger.io/v2/swagger.json ./my-project
```

Options:
- `--skip-ci`: Skip generation of GitHub Actions CI workflow.

### Generate Client Code
Generate just the Zig client code from a spec file.

```bash
openapi-gen generate path/to/openapi.json ./src/generated
```

### Generate CI Workflow
Generate a GitHub Actions CI workflow for an existing project.

```bash
openapi-gen ci-init .
```

### Build and Run Generator

```bash
zig build run -- [path/to/spec.json] [output/directory]
```

Example:

```bash
zig build run -- specs/simple.json src/generated/simple
```

### Using the Generated Client

```zig
const std = @import("std");
const Client = @import("src/generated/simple/root.zig").Client;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client = try Client.init(allocator, "http://localhost:8080", .{});
    defer client.deinit();

    // Make a request
    const response = try client.getUser("jdoe");
    switch (response) {
        .ok => |r| {
            std.debug.print("User: {s}\n", .{r.body.name});
        },
        .not_found => {
            std.debug.print("User not found\n", .{});
        },
        else => |r| {
             std.debug.print("Unexpected status: {}\n", .{r.headers.status});
        }
    }
}
```

## Development

*   **Run Tests**: `zig build test`
*   **Format Code**: `zig fmt .`
