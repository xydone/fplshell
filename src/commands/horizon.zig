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

const FixtureTable = @import("../components/fixture_table.zig");

const CommandParams = @import("command.zig").Params;
const Command = @import("command.zig");

const Allocator = std.mem.Allocator;
const std = @import("std");

test "Command | Horizon (regular)" {
    const test_name = "Command | Horizon (regular)";
    const Benchmark = @import("../test_runner.zig").Benchmark;
    const allocator = std.testing.allocator;
    var table = try FixtureTable.init(
        allocator,
        0,
        2,
    );
    defer table.deinit(allocator);

    const input = "horizon 4 10";
    var it = std.mem.tokenizeSequence(u8, input, " ");
    const command = it.next().?;

    const params = Params{
        .it = &it,
        .allocator = allocator,
        .fixture_table = &table,
    };

    var benchmark = Benchmark.start(test_name);
    defer benchmark.end();

    handle(command, params) catch |err| {
        benchmark.fail(err);
        return err;
    };

    std.testing.expectEqual(4, table.start_index) catch |err| {
        benchmark.fail(err);
        return err;
    };

    std.testing.expectEqual(10, table.end_index) catch |err| {
        benchmark.fail(err);
        return err;
    };
}

test "Command | Horizon (above max)" {
    const test_name = "Command | Horizon (above max)";
    const Benchmark = @import("../test_runner.zig").Benchmark;
    const allocator = std.testing.allocator;
    var table = try FixtureTable.init(
        allocator,
        0,
        2,
    );
    defer table.deinit(allocator);

    const input = "horizon 4 40";
    var it = std.mem.tokenizeSequence(u8, input, " ");
    const command = it.next().?;

    const params = Params{
        .it = &it,
        .allocator = allocator,
        .fixture_table = &table,
    };

    var benchmark = Benchmark.start(test_name);
    defer benchmark.end();

    handle(command, params) catch |err| switch (err) {
        error.InvalidRange => {},
        else => {
            benchmark.fail(err);
            return err;
        },
    };
}

test "Command | Horizon (below min)" {
    const test_name = "Command | Horizon (below min)";
    const Benchmark = @import("../test_runner.zig").Benchmark;
    const allocator = std.testing.allocator;
    var table = try FixtureTable.init(
        allocator,
        0,
        2,
    );
    defer table.deinit(allocator);

    const input = "horizon 0 5";
    var it = std.mem.tokenizeSequence(u8, input, " ");
    const command = it.next().?;

    const params = Params{
        .it = &it,
        .allocator = allocator,
        .fixture_table = &table,
    };

    var benchmark = Benchmark.start(test_name);
    defer benchmark.end();

    handle(command, params) catch |err| switch (err) {
        error.InvalidRange => {},
        else => {
            benchmark.fail(err);
            return err;
        },
    };
}

test "Command | Horizon (no end argument)" {
    const test_name = "Command | Horizon (no end argument)";
    const Benchmark = @import("../test_runner.zig").Benchmark;
    const allocator = std.testing.allocator;
    var table = try FixtureTable.init(
        allocator,
        0,
        2,
    );
    defer table.deinit(allocator);

    const input = "horizon 0";
    var it = std.mem.tokenizeSequence(u8, input, " ");
    const command = it.next().?;

    const params = Params{
        .it = &it,
        .allocator = allocator,
        .fixture_table = &table,
    };

    var benchmark = Benchmark.start(test_name);
    defer benchmark.end();

    handle(command, params) catch |err| switch (err) {
        error.EmptyEndToken => {},
        else => {
            benchmark.fail(err);
            return err;
        },
    };
}

test "Command | Horizon (no start argument)" {
    const test_name = "Command | Horizon (no start argument)";
    const Benchmark = @import("../test_runner.zig").Benchmark;
    const allocator = std.testing.allocator;
    var table = try FixtureTable.init(
        allocator,
        0,
        2,
    );
    defer table.deinit(allocator);

    const input = "horizon";
    var it = std.mem.tokenizeSequence(u8, input, " ");
    const command = it.next().?;

    const params = Params{
        .it = &it,
        .allocator = allocator,
        .fixture_table = &table,
    };

    var benchmark = Benchmark.start(test_name);
    defer benchmark.end();

    handle(command, params) catch |err| switch (err) {
        error.EmptyStartToken => {},
        else => {
            benchmark.fail(err);
            return err;
        },
    };
}
