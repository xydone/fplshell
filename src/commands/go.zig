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

pub fn handle(cmd: []const u8, params: Params) Errors!void {
    if (shouldCall(cmd)) {
        try call(params);
    }
}

const Table = @import("../components/player_table.zig");

const CommandParams = @import("command.zig").Params;
const Command = @import("command.zig");

const std = @import("std");

test "Command | Go (regular)" {
    const test_name = "Command | Go (regular)";
    const Benchmark = @import("../test_runner.zig").Benchmark;
    const allocator = std.testing.allocator;
    var table = try Table.init(allocator, "Sample text");
    defer table.deinit(allocator);

    const input = "go 10";
    var it = std.mem.tokenizeSequence(u8, input, " ");
    const command = it.next().?;

    const params = Params{ .players_table = &table, .it = &it };

    var benchmark = Benchmark.start(test_name);
    defer benchmark.end();

    handle(command, params) catch |err| {
        benchmark.fail(err);
        return err;
    };

    std.testing.expectEqual(10, table.table.context.row) catch |err| {
        benchmark.fail(err);
        return err;
    };
}

test "Command | Go (negative)" {
    const test_name = "Command | Go (negative)";
    const Benchmark = @import("../test_runner.zig").Benchmark;
    const allocator = std.testing.allocator;
    var table = try Table.init(allocator, "Sample text");
    defer table.deinit(allocator);

    const input = "go -10";
    var it = std.mem.tokenizeSequence(u8, input, " ");
    const command = it.next().?;

    const params = Params{ .players_table = &table, .it = &it };

    var benchmark = Benchmark.start(test_name);
    defer benchmark.end();

    handle(command, params) catch |err| switch (err) {
        error.TokenNaN => {},
        else => {
            benchmark.fail(err);
            return err;
        },
    };
}

test "Command | Go (formatting)" {
    const test_name = "Command | Go (formatting)";
    const Benchmark = @import("../test_runner.zig").Benchmark;
    const allocator = std.testing.allocator;
    var table = try Table.init(allocator, "Sample text");
    defer table.deinit(allocator);

    const input = "go 10_000";
    var it = std.mem.tokenizeSequence(u8, input, " ");
    const command = it.next().?;

    const params = Params{ .players_table = &table, .it = &it };

    var benchmark = Benchmark.start(test_name);
    defer benchmark.end();

    handle(command, params) catch |err| {
        benchmark.fail(err);
        return err;
    };

    std.testing.expectEqual(10_000, table.table.context.row) catch |err| {
        benchmark.fail(err);
        return err;
    };
}
