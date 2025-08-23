var COMMANDS = [_][]const u8{"save"};
var PARAMS = [_]CommandParams{
    .{
        .name = "<string>",
        .description = "The name of the transfer plan.",
    },
};

const base_path = "data/plans/";

pub const description = Command{
    .phrases = &COMMANDS,
    .description = "Saves the current transfer plan",
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
    allocator: std.mem.Allocator,
    season_selection: SeasonSelection,
};

pub const Errors = error{
    EmptyName,
    OOM,
    CannotSave,
};

fn call(params: Params) Errors!void {
    const allocator = params.allocator;
    const it = params.it;
    const season_selection = params.season_selection;

    const name = it.next() orelse return error.EmptyName;

    const file_path = std.fmt.allocPrint(allocator, "{s}/{s}.json", .{ base_path, name }) catch return error.OOM;
    defer allocator.free(file_path);

    var players: [GAMEWEEK_COUNT][15]?Player = undefined;
    for (season_selection.gameweek_selections, 0..) |gw_selection, i| {
        players[i] = gw_selection.players;
    }

    saveStructToFile(allocator, [GAMEWEEK_COUNT][15]?Player, players, file_path) catch return error.CannotSave;
}

pub fn handle(cmd: []const u8, params: Params) Errors!void {
    if (shouldCall(cmd)) {
        try call(params);
    }
}

const saveStructToFile = @import("../util/saveStructToFile.zig").saveStructToFile;

const Player = @import("../types.zig").Player;
const GAMEWEEK_COUNT = @import("../types.zig").GAMEWEEK_COUNT;

const GameweekSelection = @import("../gameweek_selection.zig");
const SeasonSelection = @import("../season_selection.zig");
const CommandParams = @import("command.zig").Params;
const Command = @import("command.zig");

const std = @import("std");
