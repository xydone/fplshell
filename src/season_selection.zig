gameweek_selections: [GAMEWEEK_COUNT]GameweekSelection,
fixture_table: [GAMEWEEK_COUNT]FixtureTable,

active_idx: u8,

const Self = @This();

pub fn init(allocator: Allocator, range: u8) !Self {
    const gameweek_selections = [_]GameweekSelection{GameweekSelection.init()} ** GAMEWEEK_COUNT;
    var fixture_tables: [GAMEWEEK_COUNT]FixtureTable = undefined;
    for (0..GAMEWEEK_COUNT) |i| {
        fixture_tables[i] = try .init(allocator, @intCast(i + 1), @intCast(i + 1 + range));
    }
    return .{
        .gameweek_selections = gameweek_selections,
        .fixture_table = fixture_tables,
        .active_idx = 0,
    };
}

pub fn deinit(self: Self, allocator: Allocator) void {
    inline for (self.fixture_table) |fixture_table| {
        fixture_table.deinit(allocator);
    }
}

pub fn incrementIndex(self: *Self, amount: u8) void {
    self.active_idx = std.math.clamp(self.active_idx + amount, 0, GAMEWEEK_COUNT - 1);
}

pub fn decrementIndex(self: *Self, amount: u8) void {
    self.active_idx = std.math.clamp(self.active_idx -| amount, 0, GAMEWEEK_COUNT - 1);
}

pub fn getActiveGameweek(self: Self) GameweekSelection {
    return self.gameweek_selections[self.active_idx];
}

pub fn getActiveFixture(self: Self) FixtureTable {
    return self.fixture_table[self.active_idx];
}

pub fn insertGameweek(self: *Self, gw_selection: GameweekSelection, gw_num: u8) void {
    self.gameweek_selections[gw_num] = gw_selection;
}

const FixtureTable = @import("components/fixture_table.zig");

const GAMEWEEK_COUNT = @import("types.zig").GAMEWEEK_COUNT;
const GameweekSelection = @import("gameweek_selection.zig");

const Allocator = std.mem.Allocator;
const std = @import("std");
