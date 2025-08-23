pub fn saveStructToFile(allocator: Allocator, T: type, value: T, path: []const u8) !void {
    const file = std.fs.cwd().createFile(path, .{}) catch |err| file: {
        switch (err) {
            // if the parent folder is not found, FileNotFound is thrown.
            error.FileNotFound => {
                // fs.path.dirname() returns null if the path is the root dir
                const dirname = std.fs.path.dirname(path) orelse return err;
                // create the dir
                try std.fs.cwd().makeDir(dirname);
                // retry creating the file
                break :file try std.fs.cwd().createFile(path, .{});
            },
            else => return err,
        }
    };

    const body_string = try std.json.stringifyAlloc(allocator, value, .{});
    defer allocator.free(body_string);

    _ = try file.writeAll(body_string);
}

const Allocator = std.mem.Allocator;
const std = @import("std");
