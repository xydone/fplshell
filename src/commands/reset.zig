const std = @import("std");
const Table = @import("../components/table.zig");
const Player = @import("../lineup.zig").Player;

const COMMANDS = [_][]const u8{ "reset", "r", "res" };

fn shouldCall(cmd: []const u8) bool {
    for (COMMANDS) |c| {
        if (std.mem.eql(u8, c, cmd)) return true;
    }
    return false;
}

pub const Params = struct {
    filtered_players: *std.ArrayList(Player),
    all_players: *std.ArrayList(Player),
};

pub const Errors = error{OOM};

fn call(params: Params) Errors!void {
    params.filtered_players.clearAndFree();
    params.filtered_players.appendSlice(params.all_players.items) catch return error.OOM;
}

pub fn handle(cmd: []const u8, params: Params) Errors!bool {
    const should_call = shouldCall(cmd);
    if (should_call) {
        try call(params);
    }
    return should_call;
}
