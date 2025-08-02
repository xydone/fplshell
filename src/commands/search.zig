const std = @import("std");
const Allocator = std.mem.Allocator;

const Table = @import("../components/table.zig");
const Player = @import("../lineup.zig").Player;

const COMMANDS = [_][]const u8{ "search", "s" };

fn shouldCall(cmd: []const u8) bool {
    for (COMMANDS) |c| {
        if (std.mem.eql(u8, c, cmd)) return true;
    }
    return false;
}

pub const Params = struct {
    allocator: Allocator,
    it: std.mem.TokenIterator(u8, .sequence),
    player_table: *Table,
    filtered_players: *std.ArrayList(Player),
    player_map: std.StringHashMapUnmanaged(Player),
};

pub const Errors = error{ EmptyString, OOM };

fn call(params: Params) Errors!void {
    const allocator = params.allocator;
    const it = params.it;
    const player_table = params.player_table;
    const filtered_players = params.filtered_players;
    const player_map = params.player_map;

    const string = it.rest();
    player_table.moveTo(0);

    // if nothing has been entered, just continue early
    if (string.len == 0) return error.EmptyString;
    filtered_players.clearRetainingCapacity();

    const input = std.ascii.allocLowerString(allocator, string) catch return error.OOM;
    var player_it = player_map.iterator();
    while (player_it.next()) |entry| {
        const entry_name = std.ascii.allocLowerString(allocator, entry.key_ptr.*) catch return error.OOM;

        if (std.mem.containsAtLeast(u8, entry_name, 1, input)) {
            filtered_players.append(entry.value_ptr.*) catch return error.OOM;
        }
    }
}

pub fn handle(cmd: []const u8, params: Params) Errors!bool {
    const should_call = shouldCall(cmd);
    if (should_call) {
        try call(params);
    }
    return should_call;
}
