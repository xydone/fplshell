const std = @import("std");
const Table = @import("../components/player_table.zig");
const Player = @import("../lineup.zig").Player;

const COMMANDS = [_][]const u8{"sort"};

fn shouldCall(cmd: []const u8) bool {
    for (COMMANDS) |c| {
        if (std.mem.eql(u8, c, cmd)) return true;
    }
    return false;
}

pub const Params = struct {
    it: *std.mem.TokenIterator(u8, .sequence),
    filtered_players: *std.ArrayList(Player),
};

pub const Errors = error{ EmptyString, UnknownSortType, OOM };

fn call(params: Params) Errors!void {
    const it = params.it;
    const filtered_players = params.filtered_players;

    const string = it.rest();
    // if nothing has been entered, just continue early
    if (string.len == 0) return error.EmptyString;
    const items = filtered_players.items;
    filtered_players.clearRetainingCapacity();

    const SortTypes = enum { desc, asc };
    const sort = std.meta.stringToEnum(SortTypes, string) orelse return error.UnknownSortType;
    switch (sort) {
        .asc => {
            std.mem.sort(Player, items, {}, Player.lessThan);
        },
        .desc => {
            std.mem.sort(Player, items, {}, Player.greaterThan);
        },
    }
    for (items) |player| {
        filtered_players.append(player) catch return error.OOM;
    }
}

pub fn handle(cmd: []const u8, params: Params) Errors!bool {
    const should_call = shouldCall(cmd);
    if (should_call) {
        try call(params);
    }
    return should_call;
}
