const std = @import("std");
const Allocator = std.mem.Allocator;

pub const TeamConfig = struct {
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
};

pub fn getTeam(allocator: Allocator, config_path: []const u8) !std.json.Parsed(TeamConfig) {
    const file = try std.fs.cwd().readFileAlloc(allocator, config_path, 1024 * 5);
    defer allocator.free(file);

    return try std.json.parseFromSlice(TeamConfig, allocator, file, .{
        .allocate = .alloc_always,
        .ignore_unknown_fields = true,
    });
}
