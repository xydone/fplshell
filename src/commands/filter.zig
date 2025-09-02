var COMMANDS = [_][]const u8{"filter"};

var PARAMS = [_]CommandParams{
    .{
        .name = "filter=value",
        .description = "The type of filter you want to apply. ",
        .count = .{ .unlimited = {} },
    },
};

pub const description = Command{
    .phrases = &COMMANDS,
    .description = "Applies filters on the player data. In case of duplicates, the last entry counts.",
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

pub const Errors = error{
    OOM,
    MissingValue,
    InvalidFilter,
} || PriceErrors || PositionErrors;

const Filters = enum(u8) {
    position,
    price,
};

const PriceErrors = error{
    StartPriceInvalid,
    EndPriceInvalid,
    /// Only returned when there is no price range and one single price is filtered
    PriceInvalid,
    RangeMissing,
};

const PositionErrors = error{
    InvalidPosition,
};
fn call(params: Params) Errors!void {
    const it = params.it;
    const player_table = params.player_table;
    const filtered_players = params.filtered_players;
    const all_players = params.all_players;

    const string = it.rest();

    var filters = std.mem.tokenizeScalar(u8, string, ' ');
    while (filters.next()) |filter_string| {
        var tokens = std.mem.tokenizeScalar(u8, filter_string, '=');
        const command = tokens.next().?;
        const value = tokens.next() orelse return error.MissingValue;

        const filter = std.meta.stringToEnum(Filters, command) orelse return error.InvalidFilter;

        player_table.table.moveTo(0);
        switch (filter) {
            .position => {
                const pos = std.meta.stringToEnum(Position, value) orelse return error.InvalidPosition;
                // flush table
                filtered_players.clearRetainingCapacity();
                for (all_players.items) |player| {
                    if (player.position.? == pos) filtered_players.append(player) catch return error.OOM;
                }
            },
            .price => blk: {
                // "If `delimiter` does not exist in buffer"
                var value_tokens = std.mem.tokenizeSequence(u8, value, "..");
                const start_token = value_tokens.next();
                const end_token = value_tokens.next();

                // if we have two null values, this means we do a single price filter (effectively start=price=end)
                // NOTE: exits early
                if (start_token) |token| if (token.len == value.len) {
                    const price = std.fmt.parseFloat(f32, value) catch return error.PriceInvalid;
                    // flush table
                    filtered_players.clearRetainingCapacity();
                    for (all_players.items) |player| if (player.price.? == price) filtered_players.append(player) catch return error.OOM;
                    break :blk;
                };

                const start: ?f32, const end: ?f32 = try struct {
                    /// asserts we have a valid range
                    pub fn fromStrings(start_string: ?[]const u8, end_string: ?[]const u8) !std.meta.Tuple(&.{ ?f32, ?f32 }) {
                        std.debug.assert(start_string != null or end_string != null);
                        return .{
                            if (start_string) |str| std.fmt.parseFloat(f32, str) catch return error.StartPriceInvalid else null,
                            if (end_string) |str| std.fmt.parseFloat(f32, str) catch return error.EndPriceInvalid else null,
                        };
                    }
                }.fromStrings(start_token, end_token);

                // flush table
                filtered_players.clearRetainingCapacity();
                for (all_players.items) |player| {
                    const price = player.price.?;
                    // checks if start <= value <= end is true with short circuiting
                    if ((start == null or price >= start.?) and (end == null or price <= end.?)) filtered_players.append(player) catch return error.OOM;
                }
            },
        }
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
