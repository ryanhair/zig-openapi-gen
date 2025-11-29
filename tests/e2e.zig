const std = @import("std");
const testing = std.testing;

// Import generated clients
const simple = @import("simple");
const advanced = @import("advanced");

test "Simple Client - User Struct" {
    const user = simple.User{
        .id = 1,
        .username = "testuser",
        .isActive = true,
    };

    try testing.expectEqual(@as(i64, 1), user.id);
    try testing.expectEqualStrings("testuser", user.username);
    try testing.expect(user.isActive.?);
}

test "Advanced Client - Enums and Unions" {
    const status = advanced.Status.active;
    try testing.expect(status == .active);

    const cat = advanced.Cat{ .meow = true, .type = "Cat" };
    const pet = advanced.Pet{ .Cat = cat };

    switch (pet) {
        .Cat => |c| try testing.expect(c.meow.?),
        .Dog => try testing.expect(false),
    }

    const json =
        \\{
        \\  "type": "Cat",
        \\  "meow": true
        \\}
    ;
    const parsed = try std.json.parseFromSlice(advanced.Pet, testing.allocator, json, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    switch (parsed.value) {
        .Cat => |c| try testing.expect(c.meow.?),
        .Dog => try testing.expect(false),
    }
}

test "Advanced Client - AnyOf, Number, AdditionalProperties" {
    const any_of = advanced.AnyOfStruct{ .Cat = .{ .meow = true, .type = "Cat" } };
    switch (any_of) {
        .Cat => |c| try testing.expect(c.meow.?),
        .Dog => try testing.expect(false),
    }

    const num_struct = advanced.NumberStruct{ .value = 123.45, .intVal = 100 };
    try testing.expectEqual(@as(f64, 123.45), num_struct.value.?);
    try testing.expectEqual(@as(i64, 100), num_struct.intVal.?);

    const dict_struct = advanced.DictStruct{};
    // We can't easily test dynamic props without a full JSON roundtrip or manual map construction
    // checking default value
    try testing.expect(dict_struct.extraProps == null);
}

test "Advanced Client - Multipart and UrlEncoded" {
    const allocator = testing.allocator;
    var client = try advanced.Client.init(allocator, .{}, .{ .base_url = "http://localhost:19283" });
    defer client.deinit();

    // Test UploadFile (Multipart)
    const file_content = "Hello World";
    const upload_body = advanced.UploadFile{
        .file = file_content,
        .description = "Test file",
    };
    // We expect ConnectionRefused because there is no server
    try testing.expectError(error.ConnectionRefused, client.uploadFile(upload_body));

    // Test SubmitForm (UrlEncoded)
    const form_body = advanced.SubmitForm{
        .field1 = "value1",
        .field2 = "value2",
    };
    try testing.expectError(error.ConnectionRefused, client.submitForm(form_body));
}

test "Advanced Client - Validation" {
    const allocator = std.testing.allocator;
    const auth_config = advanced.AuthConfig{};
    var client = try advanced.Client.init(allocator, auth_config, .{ .base_url = "http://localhost:19283" });
    defer client.deinit();

    // 1. Valid data
    const valid_data = advanced.ValidatedStruct{
        .stringVal = "hello", // len 5
        .intVal = 50,
        .requiredField = "present",
    };
    // This should fail with ConnectionRefused, NOT ValidationError
    try testing.expectError(error.ConnectionRefused, client.validateData(valid_data));

    // 2. Invalid string length (too short)
    const invalid_string = advanced.ValidatedStruct{
        .stringVal = "hi", // len 2 < 5
        .intVal = 50,
        .requiredField = "present",
    };
    try testing.expectError(error.ValidationError, client.validateData(invalid_string));

    // 3. Invalid number (too small)
    const invalid_number = advanced.ValidatedStruct{
        .stringVal = "hello",
        .intVal = 5, // < 10
        .requiredField = "present",
    };
    try testing.expectError(error.ValidationError, client.validateData(invalid_number));
}

test "Advanced Client - Server Configuration" {
    const allocator = std.testing.allocator;
    const auth_config = advanced.AuthConfig{};

    // 1. Default server (index 0)
    {
        var client = try advanced.Client.init(allocator, auth_config, .{});
        defer client.deinit();
        try std.testing.expectEqualStrings("https://api.example.com/v1", client.base_url);
    }

    // 2. Server with variables (index 1)
    {
        var client = try advanced.Client.init(allocator, auth_config, .{
            .server_index = 1,
            .server_vars = .{ .port = "9090" },
        });
        defer client.deinit();
        try std.testing.expectEqualStrings("http://localhost:9090", client.base_url);
    }

    // 3. Server with variables (index 0, custom env)
    {
        var client = try advanced.Client.init(allocator, auth_config, .{
            .server_index = 0,
            .server_vars = .{ .environment = "staging" },
        });
        defer client.deinit();
        try std.testing.expectEqualStrings("https://staging.example.com/v1", client.base_url);
    }
}

test "Advanced Client - Recursive Validation" {
    const allocator = std.testing.allocator;
    const auth_config = advanced.AuthConfig{};
    var client = try advanced.Client.init(allocator, auth_config, .{ .base_url = "http://localhost:19283" });
    defer client.deinit();

    // 1. Valid nested data
    const valid_child = advanced.ValidatedStruct{
        .stringVal = "hello",
        .intVal = 50,
        .requiredField = "present",
    };
    const valid_parent = advanced.ParentStruct{
        .child = valid_child,
        .children = null,
    };
    // Should pass validation (and fail connection)
    try testing.expectError(error.ConnectionRefused, client.validateRecursive(valid_parent));

    // 2. Invalid nested data (child invalid)
    const invalid_child = advanced.ValidatedStruct{
        .stringVal = "hi", // Too short
        .intVal = 50,
        .requiredField = "present",
    };
    const invalid_parent = advanced.ParentStruct{
        .child = invalid_child,
        .children = null,
    };
    // Should fail validation
    try testing.expectError(error.ValidationError, client.validateRecursive(invalid_parent));

    // 3. Invalid array item
    const valid_child2 = advanced.ValidatedStruct{
        .stringVal = "hello",
        .intVal = 50,
        .requiredField = "present",
    };
    const invalid_child2 = advanced.ValidatedStruct{
        .stringVal = "hello",
        .intVal = 5, // Too small
        .requiredField = "present",
    };
    const children = [_]advanced.ValidatedStruct{ valid_child2, invalid_child2 };
    const invalid_parent_array = advanced.ParentStruct{
        .child = valid_child,
        .children = &children,
    };
    // Should fail validation
    try testing.expectError(error.ValidationError, client.validateRecursive(invalid_parent_array));
}
