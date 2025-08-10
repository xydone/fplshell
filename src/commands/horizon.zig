const std = @import("std");
const Allocator = std.mem.Allocator;

const FixtureTable = @import("../components/fixture_table.zig");

const CommandParams = @import("command.zig").Params;
const Command = @import("command.zig");

var COMMANDS = [_][]const u8{"horizon"};
var PARAMS = [_]CommandParams{
    .{
        .name = "<number>",
        .description = "The start of the horizon",
    },
    .{
        .name = "<number>",
        .description = "The end of the horizon",
    },
};

pub const description = Command{
    .phrases = &COMMANDS,
    .description = "Changes the gameweek horizon.",
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
    fixture_table: *FixtureTable,
    allocator: Allocator,
};

pub const Errors = error{ EmptyStartToken, StartTokenNaN, EmptyEndToken, EndTokenNaN, InvalidRange };

fn call(params: Params) Errors!void {
    const allocator = params.allocator;
    const it = params.it;
    const fixture_table = params.fixture_table;

    const start_token = it.next() orelse return error.EmptyStartToken;
    const start = std.fmt.parseInt(u8, start_token, 10) catch return error.StartTokenNaN;
    const end_token = it.next() orelse return error.EmptyEndToken;
    const end = std.fmt.parseInt(u8, end_token, 10) catch return error.EndTokenNaN;

    fixture_table.setRange(allocator, start, end) catch return error.InvalidRange;
}

pub fn handle(cmd: []const u8, params: Params) Errors!void {
    if (shouldCall(cmd)) {
        try call(params);
    }
}
