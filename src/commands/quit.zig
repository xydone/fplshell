const std = @import("std");
const Table = @import("../components/player_table.zig");

const CommandParams = @import("command.zig").Params;
const Command = @import("command.zig");

var COMMANDS = [_][]const u8{ "quit", "q", "exit" };

pub const description = Command{
    .phrases = &COMMANDS,
    .description = "Closes the program.",
    .params = null,
};

pub fn shouldCall(cmd: []const u8) bool {
    for (COMMANDS) |c| {
        if (std.mem.eql(u8, c, cmd)) return true;
    }
    return false;
}
