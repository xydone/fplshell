team_source: union(enum) {
    team_id: u32,
    file: void, // TODO: this is stupid
},

const config_path = "config/config.json";
const Self = @This();

pub fn get(allocator: Allocator) !std.json.Parsed(Self) {
    return readFile(Self, allocator, config_path, 1024);
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

    const path = "config/team.json";

    pub fn get(allocator: Allocator) !std.json.Parsed(TeamFile) {
        return readFile(TeamFile, allocator, path, 1024 * 5);
    }
};

pub const ColorsFile = struct {
    const path = "config/team_colors.json";

    pub fn get(allocator: Allocator) !std.json.Parsed([][3]u8) {
        return readFile([][3]u8, allocator, path, 1024);
    }
};

fn readFile(T: type, allocator: Allocator, path: []const u8, max_bytes: u32) !std.json.Parsed(T) {
    const file = try std.fs.cwd().readFileAlloc(allocator, path, max_bytes);
    defer allocator.free(file);

    return std.json.parseFromSlice(T, allocator, file, .{
        .allocate = .alloc_always,
        .ignore_unknown_fields = true,
    });
}

const Color = @import("colors.zig").Color;
const Allocator = std.mem.Allocator;
const std = @import("std");
