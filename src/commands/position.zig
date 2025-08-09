const std = @import("std");
const Allocator = std.mem.Allocator;

const Table = @import("../components/player_table.zig");
const Player = @import("../lineup.zig").Player;
const Position = Player.Position;

const CommandParams = @import("command.zig").Params;
const Command = @import("command.zig");

const enumToString = @import("../util/enumToString.zig").enumToString;

var COMMANDS = [_][]const u8{ "position", "pos" };

var PARAMS = [_]CommandParams{
    .{
        .name = enumToString(Position),
        .description = "The position you want to filter by.",
    },
};

pub const description = Command{
    .phrases = &COMMANDS,
    .description = "Filters the player database by positions",
    .params = &PARAMS,
};

fn shouldCall(cmd: []const u8) bool {
    for (COMMANDS) |c| {
        if (std.mem.eql(u8, c, cmd)) return true;
    }
    return false;
}

pub fn handle(cmd: []const u8, params: Params) Errors!bool {
    const should_call = shouldCall(cmd);
    if (should_call) {
        try call(params);
    }
    return should_call;
}

pub const Params = struct {
    it: std.mem.TokenIterator(u8, .sequence),
    player_table: *Table,
    filtered_players: *std.ArrayList(Player),
    all_players: std.ArrayList(Player),
};

pub const Errors = error{ EmptyString, InvalidPosition, OOM };

fn call(params: Params) Errors!void {
    const it = params.it;
    const player_table = params.player_table;
    const filtered_players = params.filtered_players;
    const all_players = params.all_players;

    const string = it.rest();
    player_table.table.moveTo(0);

    // if nothing has been entered, just continue early
    if (string.len == 0) return error.EmptyString;

    const pos = std.meta.stringToEnum(Position, string) orelse return error.InvalidPosition;
    // flush table
    filtered_players.clearRetainingCapacity();
    for (all_players.items) |player| {
        if (player.position.? == pos) filtered_players.append(player) catch return error.OOM;
    }
}
