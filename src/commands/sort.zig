const std = @import("std");
const Table = @import("../components/player_table.zig");
const Player = @import("../selection.zig").Player;

const CommandParams = @import("command.zig").Params;
const Command = @import("command.zig");

const enumToString = @import("../util/enumToString.zig").enumToString;

const SortTypes = enum { desc, asc };

var COMMANDS = [_][]const u8{"sort"};

var PARAMS = [_]CommandParams{
    .{
        .name = enumToString(SortTypes),
        .description = "The sort type.",
    },
};

pub const description = Command{
    .phrases = &COMMANDS,
    .description = "Sorts the player database by price.", //NOTE: update this when sorting is implemented for other things like EV
    .params = &PARAMS,
};

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

pub fn handle(cmd: []const u8, params: Params) Errors!void {
    if (shouldCall(cmd)) {
        try call(params);
    }
}
