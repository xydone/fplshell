gameweek_selections: *[GAMEWEEK_COUNT]GameweekSelection,
fixture_table: [GAMEWEEK_COUNT]FixtureTable,

active_idx: u8,

const Self = @This();

pub fn init(allocator: Allocator, range: u8) !Self {
    // const gameweek_selections = [_]GameweekSelection{GameweekSelection.init()} ** GAMEWEEK_COUNT;
    const gameweek_selections = try allocator.create([GAMEWEEK_COUNT]GameweekSelection);
    for (gameweek_selections) |*gw_selection| {
        gw_selection.* = .init();
    }
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
    allocator.free(self.gameweek_selections);
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

//TODO: make this work with wildcards/free hits
pub fn removePlayer(self: *Self, index: u32) void {
    const player = self.gameweek_selections[self.active_idx].players[index] orelse return;
    var are_free_transfers_adjusted = false;
    for (self.gameweek_selections[self.active_idx..]) |*gameweek| {
        gameweek.remove(player.id.?);
        const transfer_amount_before_update = gameweek.free_transfers;

        if (transfer_amount_before_update == 0) {
            gameweek.takeHit(1);
            break;
        }

        if (are_free_transfers_adjusted == false) gameweek.removeFreeTransfers(1);

        if (transfer_amount_before_update == MAX_FREE_TRANSFERS) are_free_transfers_adjusted = true;
    }
}

pub const AppendErrors = error{ SelectionFull, MissingFunds };
pub const AppendOptions = struct {
    /// if true, appends will propagate to future gameweeks
    propagate: bool = false,
};

pub fn appendPlayer(self: *Self, player: Player, options: AppendOptions) AppendErrors!void {
    try self.gameweek_selections[self.active_idx].append(player);
    if (options.propagate) {
        for (self.gameweek_selections[self.active_idx + 1 ..]) |*gw_selection| {
            gw_selection.append(player) catch break;
        }
    }
}

pub fn swapPlayers(self: *Self, first_idx: u16, second_idx: u16) void {
    std.mem.swap(
        ?Player,
        &self.gameweek_selections[self.active_idx].players[first_idx],
        &self.gameweek_selections[self.active_idx].players[second_idx],
    );
    self.gameweek_selections[self.active_idx].is_valid_formation = self.gameweek_selections[self.active_idx].isValidFormation();
}

const FixtureTable = @import("components/fixture_table.zig");

const Player = @import("types.zig").Player;

const MAX_FREE_TRANSFERS = @import("types.zig").MAX_FREE_TRANSFERS;
const GAMEWEEK_COUNT = @import("types.zig").GAMEWEEK_COUNT;
const GameweekSelection = @import("gameweek_selection.zig");

const Allocator = std.mem.Allocator;
const std = @import("std");
