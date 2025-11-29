const std = @import("std");
const fetch = @import("fetch.zig");
const parser = @import("parser.zig");
const generator = @import("generator.zig");

const ui = @import("ui.zig");

pub fn generateProject(allocator: std.mem.Allocator, spec_source: []const u8, output_dir_path: []const u8, skip_ci: bool) !void {
    // 1. Create output directory
    try std.fs.cwd().makePath(output_dir_path);
    var output_dir = try std.fs.cwd().openDir(output_dir_path, .{});
    defer output_dir.close();

    // 2. Fetch or copy spec
    const spec_content = if (std.mem.startsWith(u8, spec_source, "http://") or std.mem.startsWith(u8, spec_source, "https://"))
        try fetch.fetchSpec(allocator, spec_source)
    else blk: {
        ui.printInfo("Reading spec from file: {s}", .{spec_source});
        const file = try std.fs.cwd().openFile(spec_source, .{});
        defer file.close();
        break :blk try file.readToEndAlloc(allocator, 1024 * 1024 * 10);
    };
    defer allocator.free(spec_content);

    // 3. Generate Client Code
    // Create src directory
    try output_dir.makePath("src");
    var src_dir = try output_dir.openDir("src", .{});
    defer src_dir.close();

    {
        var spinner = ui.Spinner.init(allocator, "Generating client code...");
        try spinner.start();
        defer spinner.stop();

        var parsed_spec = try parser.parse(allocator, spec_content);
        defer parsed_spec.deinit();

        try generator.generate(allocator, parsed_spec.value, src_dir);
    }

    // 4. Generate Build Files
    try writeFile(output_dir, "build.zig", build_zig_template);

    // Initial build.zig.zon with dummy fingerprint
    const dummy_fingerprint: u64 = 0;
    const zon_content = try std.fmt.allocPrint(allocator, build_zig_zon_template, .{dummy_fingerprint});
    defer allocator.free(zon_content);
    try writeFile(output_dir, "build.zig.zon", zon_content);

    try writeFile(output_dir, ".gitignore", gitignore_template);
    try writeFile(output_dir, "README.md", readme_template);

    // Generate config file
    const config_content = try std.fmt.allocPrint(allocator, config_template, .{spec_source});
    defer allocator.free(config_content);
    try writeFile(output_dir, ".openapi-config.json", config_content);

    std.debug.print("Project initialized in {s}\n", .{output_dir_path});

    // 5. Generate CI (optional)
    if (!skip_ci) {
        try generateCI(output_dir_path);
        try generateUpdateWorkflow(output_dir_path);
    }

    // 6. Auto-fix fingerprint
    fixFingerprint(allocator, output_dir_path) catch |err| {
        std.debug.print("Warning: Failed to update fingerprint: {}\n", .{err});
        std.debug.print("You may need to run 'zig build' and update build.zig.zon manually.\n", .{});
    };
}

pub fn generateCI(output_dir_path: []const u8) !void {
    var output_dir = try std.fs.cwd().openDir(output_dir_path, .{});
    defer output_dir.close();

    const workflows_dir_path = ".github/workflows";
    try output_dir.makePath(workflows_dir_path);
    var workflows_dir = try output_dir.openDir(workflows_dir_path, .{});
    defer workflows_dir.close();

    try writeFile(workflows_dir, "ci.yml", ci_workflow_template);
    std.debug.print("CI workflow generated in {s}/.github/workflows/ci.yml\n", .{output_dir_path});
}

pub fn generateUpdateWorkflow(output_dir_path: []const u8) !void {
    var output_dir = try std.fs.cwd().openDir(output_dir_path, .{});
    defer output_dir.close();

    const workflows_dir_path = ".github/workflows";
    try output_dir.makePath(workflows_dir_path);
    var workflows_dir = try output_dir.openDir(workflows_dir_path, .{});
    defer workflows_dir.close();

    try writeFile(workflows_dir, "update.yml", update_workflow_template);
    std.debug.print("Update workflow generated in {s}/.github/workflows/update.yml\n", .{output_dir_path});
}

pub fn updateProject(allocator: std.mem.Allocator) !void {
    // 1. Read config
    const config_file = std.fs.cwd().openFile(".openapi-config.json", .{}) catch |err| {
        if (err == error.FileNotFound) {
            ui.printError("No .openapi-config.json found. Run 'openapi-gen init' to create a new project.", .{});
            return error.ConfigNotFound;
        }
        return err;
    };
    defer config_file.close();

    const config_content = try config_file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(config_content);

    const Config = struct {
        spec_url: []const u8,
        output_dir: []const u8,
    };

    const parsed_config = try std.json.parseFromSlice(Config, allocator, config_content, .{ .ignore_unknown_fields = true });
    defer parsed_config.deinit();
    const config = parsed_config.value;

    ui.printInfo("Updating client from {s}...", .{config.spec_url});

    // 2. Fetch spec
    const spec_content = try fetch.fetchSpec(allocator, config.spec_url);
    defer allocator.free(spec_content);

    // 3. Regenerate
    var output_dir = try std.fs.cwd().openDir(config.output_dir, .{});
    defer output_dir.close();

    {
        var spinner = ui.Spinner.init(allocator, "Regenerating client code...");
        try spinner.start();
        defer spinner.stop();

        var parsed_spec = try parser.parse(allocator, spec_content);
        defer parsed_spec.deinit();

        try generator.generate(allocator, parsed_spec.value, output_dir);
    }

    // 4. Update fingerprint
    fixFingerprint(allocator, ".") catch |err| {
        std.debug.print("Warning: Failed to update fingerprint: {}\n", .{err});
    };

    ui.printInfo("Client updated successfully!", .{});
}

fn fixFingerprint(allocator: std.mem.Allocator, project_path: []const u8) !void {
    const argv = [_][]const u8{ "zig", "build" };
    var child = std.process.Child.init(&argv, allocator);
    child.cwd = project_path;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Pipe;

    try child.spawn();

    // Read stderr to find the fingerprint suggestion
    var stderr = std.ArrayList(u8){};
    defer stderr.deinit(allocator);
    var buf: [4096]u8 = undefined;
    while (true) {
        const n = try child.stderr.?.read(&buf);
        if (n == 0) break;
        try stderr.appendSlice(allocator, buf[0..n]);
    }

    const term = try child.wait();

    if (term == .Exited and term.Exited == 0) {
        return; // Build succeeded, fingerprint is correct (unlikely with dummy)
    }

    const output = stderr.items;
    const needle = "use this value: 0x";
    if (std.mem.indexOf(u8, output, needle)) |idx| {
        const start = idx + needle.len;
        var end = start;
        while (end < output.len and std.ascii.isHex(output[end])) : (end += 1) {}
        const hex_str = output[start..end];
        const fingerprint = try std.fmt.parseInt(u64, hex_str, 16);

        // Update build.zig.zon
        // Note: We need to re-generate the zon content with the new fingerprint
        // Ideally we would parse and update, but for now we regenerate from template
        // This assumes the template hasn't changed other than fingerprint
        const zon_content = try std.fmt.allocPrint(allocator, build_zig_zon_template, .{fingerprint});
        defer allocator.free(zon_content);

        var dir = try std.fs.cwd().openDir(project_path, .{});
        defer dir.close();
        try writeFile(dir, "build.zig.zon", zon_content);
        std.debug.print("Updated build.zig.zon with fingerprint: 0x{x}\n", .{fingerprint});
    } else {
        return error.FingerprintNotFound;
    }
}

fn writeFile(dir: std.fs.Dir, path: []const u8, content: []const u8) !void {
    var file = try dir.createFile(path, .{});
    defer file.close();
    try file.writeAll(content);
}

const config_template =
    \\{{
    \\    "spec_url": "{s}",
    \\    "output_dir": "src",
    \\    "package_name": "client"
    \\}}
;

const ci_workflow_template =
    \\name: CI
    \\
    \\on:
    \\  push:
    \\    branches: [ "main" ]
    \\  pull_request:
    \\    branches: [ "main" ]
    \\
    \\jobs:
    \\  build:
    \\    runs-on: ubuntu-latest
    \\    steps:
    \\    - uses: actions/checkout@v4
    \\    - uses: mlugg/setup-zig@v2
    \\      with:
    \\        version: 0.15.2
    \\    - name: Build
    \\      run: zig build
    \\    - name: Run Tests
    \\      run: zig build test
;

const update_workflow_template =
    \\name: Auto Update
    \\
    \\on:
    \\  schedule:
    \\    - cron: '0 0 * * *' # Daily at midnight
    \\  workflow_dispatch:
    \\
    \\jobs:
    \\  update:
    \\    runs-on: ubuntu-latest
    \\    permissions:
    \\      contents: write
    \\    steps:
    \\    - uses: actions/checkout@v4
    \\
    \\    - uses: mlugg/setup-zig@v2
    \\      with:
    \\        version: 0.15.2
    \\
    \\    - name: Install openapi-gen
    \\      run: |
    \\        curl -sSL https://raw.githubusercontent.com/ryanhair/zig-openapi-gen/main/scripts/install.sh | bash
    \\        echo "$HOME/.local/bin" >> $GITHUB_PATH
    \\
    \\    - name: Update Client
    \\      run: openapi-gen update
    \\
    \\    - name: Check for changes
    \\      id: git-check
    \\      run: |
    \\        git diff --exit-code || echo "changes=true" >> $GITHUB_OUTPUT
    \\
    \\    - name: Commit and Push
    \\      if: steps.git-check.outputs.changes == 'true'
    \\      run: |
    \\        git config --global user.name 'github-actions[bot]'
    \\        git config --global user.email 'github-actions[bot]@users.noreply.github.com'
    \\        git add .
    \\        git commit -m "chore: update client from upstream spec"
    \\        git push
;

const build_zig_template =
    \\const std = @import("std");
    \\
    \\pub fn build(b: *std.Build) void {
    \\    const target = b.standardTargetOptions(.{});
    \\    const optimize = b.standardOptimizeOption(.{});
    \\
    \\    const mod = b.addModule("client", .{
    \\        .root_source_file = b.path("src/root.zig"),
    \\        .target = target,
    \\        .optimize = optimize,
    \\    });
    \\
    \\    const lib = b.addLibrary(.{
    \\        .linkage = .static,
    \\        .name = "client",
    \\        .root_module = mod,
    \\    });
    \\    b.installArtifact(lib);
    \\
    \\    const main_tests = b.addTest(.{
    \\        .root_module = mod,
    \\    });
    \\    const run_main_tests = b.addRunArtifact(main_tests);
    \\    const test_step = b.step("test", "Run library tests");
    \\    test_step.dependOn(&run_main_tests.step);
    \\}
;

const build_zig_zon_template =
    \\.{{
    \\    .name = .client,
    \\    .version = "0.1.0",
    \\    .minimum_zig_version = "0.15.2",
    \\    .fingerprint = 0x{x},
    \\    .dependencies = .{{
    \\    }},
    \\    .paths = .{{
    \\        "build.zig",
    \\        "build.zig.zon",
    \\        "src",
    \\        "README.md",
    \\    }},
    \\}}
;

const gitignore_template =
    \\.zig-cache/
    \\zig-out/
    \\
;

const readme_template =
    \\# Zig API Client
    \\
    \\This client was generated by [zig-openapi-gen](https://github.com/ryanhair/zig-openapi-gen).
    \\
    \\## Usage
    \\
    \\Add this package to your `build.zig.zon` and import it in your code.
    \\
    \\```zig
    \\const std = @import("std");
    \\const client = @import("client");
    \\
    \\pub fn main() !void {
    \\    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    \\    defer _ = gpa.deinit();
    \\    const allocator = gpa.allocator();
    \\
    \\    var c = try client.Client.init(allocator, "https://api.example.com", .{});
    \\    defer c.deinit();
    \\
    \\    // Use the client...
    \\}
    \\```
;
