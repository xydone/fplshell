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

pub fn handle(cmd: []const u8, params: Params) Errors!void {
    if (shouldCall(cmd)) {
        try call(params);
    }
}

const enumToString = @import("../util/enumToString.zig").enumToString;

const Table = @import("../components/player_table.zig");
const Position = Player.Position;
const Player = @import("../types.zig").Player;

const CommandParams = @import("command.zig").Params;
const Command = @import("command.zig");

const Allocator = std.mem.Allocator;
const std = @import("std");

test "Command | Position (regular)" {
    const test_name = "Command | Position (regular)";
    const Benchmark = @import("../test_runner.zig").Benchmark;
    const allocator = std.testing.allocator;

    var goalkeeper: Player = undefined;
    goalkeeper.position = .gk;

    var midfielder: Player = undefined;
    midfielder.position = .mid;

    const test_players = [_]Player{ goalkeeper, midfielder };

    var player_table = try Table.init(allocator, "sample text");
    defer player_table.deinit(allocator);

    var all_players = std.ArrayList(Player).init(allocator);
    defer all_players.deinit();

    try all_players.appendSlice(&test_players);

    var filtered_players = try all_players.clone();
    defer filtered_players.deinit();

    const input = "position gk";
    var it = std.mem.tokenizeSequence(u8, input, " ");
    const command = it.next().?;

    const params = Params{
        .it = it,
        .player_table = &player_table,
        .filtered_players = &filtered_players,
        .all_players = all_players,
    };

    var benchmark = Benchmark.start(test_name);
    defer benchmark.end();

    handle(command, params) catch |err| {
        benchmark.fail(err);
        return err;
    };

    std.testing.expectEqual(filtered_players.items.len, 1) catch |err| {
        benchmark.fail(err);
        return err;
    };

    std.testing.expectEqual(Position.gk, filtered_players.items[0].position) catch |err| {
        benchmark.fail(err);
        return err;
    };
}

test "Command | Position (empty list)" {
    const test_name = "Command | Position (empty list)";
    const Benchmark = @import("../test_runner.zig").Benchmark;
    const allocator = std.testing.allocator;

    var player_table = try Table.init(allocator, "sample text");
    defer player_table.deinit(allocator);

    var all_players = std.ArrayList(Player).init(allocator);
    defer all_players.deinit();

    var filtered_players = try all_players.clone();
    defer filtered_players.deinit();

    const input = "position gk";
    var it = std.mem.tokenizeSequence(u8, input, " ");
    const command = it.next().?;

    const params = Params{
        .it = it,
        .player_table = &player_table,
        .filtered_players = &filtered_players,
        .all_players = all_players,
    };

    var benchmark = Benchmark.start(test_name);
    defer benchmark.end();

    handle(command, params) catch |err| {
        benchmark.fail(err);
        return err;
    };

    std.testing.expectEqual(filtered_players.items.len, 0) catch |err| {
        benchmark.fail(err);
        return err;
    };
}

test "Command | Position (invalid position)" {
    const test_name = "Command | Position (invalid position)";
    const Benchmark = @import("../test_runner.zig").Benchmark;
    const allocator = std.testing.allocator;

    var player_table = try Table.init(allocator, "sample text");
    defer player_table.deinit(allocator);

    var all_players = std.ArrayList(Player).init(allocator);
    defer all_players.deinit();

    var filtered_players = try all_players.clone();
    defer filtered_players.deinit();

    const input = "position invalid";
    var it = std.mem.tokenizeSequence(u8, input, " ");
    const command = it.next().?;

    const params = Params{
        .it = it,
        .player_table = &player_table,
        .filtered_players = &filtered_players,
        .all_players = all_players,
    };

    var benchmark = Benchmark.start(test_name);
    defer benchmark.end();

    handle(command, params) catch |err| switch (err) {
        error.InvalidPosition => {},
        else => {
            benchmark.fail(err);
            return err;
        },
    };
}

test "Command | Position (no position)" {
    const test_name = "Command | Position (no position)";
    const Benchmark = @import("../test_runner.zig").Benchmark;
    const allocator = std.testing.allocator;

    var player_table = try Table.init(allocator, "sample text");
    defer player_table.deinit(allocator);

    var all_players = std.ArrayList(Player).init(allocator);
    defer all_players.deinit();

    var filtered_players = try all_players.clone();
    defer filtered_players.deinit();

    const input = "position";
    var it = std.mem.tokenizeSequence(u8, input, " ");
    const command = it.next().?;

    const params = Params{
        .it = it,
        .player_table = &player_table,
        .filtered_players = &filtered_players,
        .all_players = all_players,
    };

    var benchmark = Benchmark.start(test_name);
    defer benchmark.end();

    handle(command, params) catch |err| switch (err) {
        error.EmptyString => {},
        else => {
            benchmark.fail(err);
            return err;
        },
    };
}
