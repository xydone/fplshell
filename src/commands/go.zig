const std = @import("std");
const Table = @import("../components/player_table.zig");

const CommandParams = @import("command.zig").Params;
const Command = @import("command.zig");

var COMMANDS = [_][]const u8{ "go", "g" };
var PARAMS = [_]CommandParams{
    .{
        .name = "<number>",
        .description = "The line you want to go to.",
    },
};

pub const description = Command{
    .phrases = &COMMANDS,
    .description = "Moves the filter table to a line.",
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
    players_table: *Table,
};

pub const Errors = error{ TokenNaN, EmptyToken };

fn call(params: Params) Errors!void {
    const line_token = params.it.next() orelse return error.EmptyToken;
    const line = std.fmt.parseInt(u16, line_token, 10) catch return error.TokenNaN;
    params.players_table.table.moveTo(line);
}

pub fn handle(cmd: []const u8, params: Params) Errors!bool {
    const should_call = shouldCall(cmd);
    if (should_call) {
        try call(params);
    }
    return should_call;
}
