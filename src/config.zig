team_source: union(enum) {
    id: u32,
    file: ?[]const u8,
},

const config_path = "config/config.zon";
const Self = @This();

const log = std.log.scoped(.config);

pub fn get(allocator: Allocator) !Self {
    return readFileZon(Self, allocator, config_path, 1024 * 5) catch |err| {
        log.err("Could not read the config file!", .{});
        switch (err) {
            error.ExpectedUnion => log.err("NOTE: Check if you have .file and .id uncommented at once!", .{}),
            else => {},
        }
        return err;
    };
}
pub fn deinit(self: Self, allocator: Allocator) void {
    zon.parse.free(allocator, self);
}

pub const TeamFile = struct {
    picks: []Pick,
    picks_last_updated: []const u8,
    transfers: Transfers,
    // chips: []Chip, TODO
    const Pick = struct {
        element: u32,
        position: u32,
        multiplier: u32,
        is_captain: bool,
        is_vice_captain: bool,
        element_type: u32,
        selling_price: u32,
        purchase_price: u32,
    };
    const Transfers = struct {
        cost: u32,
        status: []const u8, //TODO: enum
        limit: ?u32,
        made: u32,
        bank: u32,
        value: u32,
    };

    const config_dir = "config/";
    const default_file_path = config_dir ++ "team.json";

    pub fn get(allocator: Allocator, file_path: ?[]const u8) !std.json.Parsed(TeamFile) {
        const path = if (file_path) |file|
            try std.fmt.allocPrint(allocator, "{s}{s}", .{ config_dir, file })
        else
            default_file_path;

        defer if (file_path) |_| allocator.free(path);
        return readFileJson(TeamFile, allocator, path, 1024 * 5);
    }
};

pub const VisualSettingsFile = struct {
    team_colors: [][3]u8,
    background_color: ?[3]u8,

    const path = "config/visual_settings.zon";

    pub fn get(allocator: Allocator) !VisualSettingsFile {
        return try readFileZon(VisualSettingsFile, allocator, path, 1024 * 5);
    }
    pub fn deinit(self: VisualSettingsFile, allocator: Allocator) void {
        zon.parse.free(allocator, self);
    }
};

const ReadFileZonErrors = error{
    CantReadFile,
    ParseZon,
    ExpectedUnion,
};
fn readFileZon(T: type, allocator: Allocator, path: []const u8, max_bytes: u32) ReadFileZonErrors!T {
    const file = std.fs.cwd().readFileAllocOptions(
        allocator,
        path,
        max_bytes,
        null,
        @alignOf(u8),
        0,
    ) catch return error.CantReadFile;
    defer allocator.free(file);

    var status: zon.parse.Status = .{};
    defer status.deinit(allocator);

    return zon.parse.fromSlice(T, allocator, file, &status, .{}) catch {
        var error_it = status.iterateErrors();
        log.debug("Zon parsing error status: {s}", .{status});
        while (error_it.next()) |status_err| {
            if (std.mem.eql(u8, "expected union", status_err.type_check.message)) return error.ExpectedUnion;
        }
        return error.ParseZon;
    };
}

fn readFileJson(T: type, allocator: Allocator, path: []const u8, max_bytes: u32) !std.json.Parsed(T) {
    const file = try std.fs.cwd().readFileAlloc(allocator, path, max_bytes);
    defer allocator.free(file);

    return std.json.parseFromSlice(T, allocator, file, .{
        .allocate = .alloc_always,
        .ignore_unknown_fields = true,
    });
}

const Color = @import("colors.zig").Color;

const zon = std.zon;
const Allocator = std.mem.Allocator;
const std = @import("std");
