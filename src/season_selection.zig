gameweek_selections: *[GAMEWEEK_COUNT]GameweekSelection,
fixture_table: [GAMEWEEK_COUNT]FixtureTable,

active_idx: u8,

const Self = @This();

pub fn init(allocator: Allocator, visual_settings: VisualSettings, range: u8) !Self {
    // const gameweek_selections = [_]GameweekSelection{GameweekSelection.init()} ** GAMEWEEK_COUNT;
    const gameweek_selections = try allocator.create([GAMEWEEK_COUNT]GameweekSelection);
    for (gameweek_selections) |*gw_selection| {
        gw_selection.* = .init();
    }
    var fixture_tables: [GAMEWEEK_COUNT]FixtureTable = undefined;
    for (0..GAMEWEEK_COUNT) |i| {
        fixture_tables[i] = try .init(allocator, visual_settings, @intCast(i + 1), @intCast(i + 1 + range));
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

pub fn activateChip(self: *Self, chip: Chips) void {
    self.gameweek_selections[self.active_idx].activateChip(chip);
    // if its a wildcard, we also need to dock 1 free transfer from future gameweeks
    // NOTE: wildcards can only be activated if a move is made
    if (chip == .wildcard) {
        for (self.gameweek_selections[self.active_idx + 1 ..]) |*gameweek| {
            gameweek.removeFreeTransfers(1);
        }
    }
}

pub fn deactivateChip(self: *Self) void {
    const chip = self.gameweek_selections[self.active_idx].chip_active orelse return;
    self.gameweek_selections[self.active_idx].deactivateChip();
    // if its a wildcard, we also need to dock 1 free transfer from future gameweeks
    // NOTE: wildcards can only be activated if a move is made
    if (chip == .wildcard) {
        for (self.gameweek_selections[self.active_idx + 1 ..]) |*gameweek| {
            gameweek.addFreeTransfers(1);
        }
    }
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
    // checks if the player was removed from the team but this function call adds him back to the team.
    // this "gives" that transfer back to the team.
    // NOTE: this will probably need to be reimplemented once calls to FPL API for actual team changes gets added.
    var is_reinsert = true;
    if (self.active_idx > 0) {
        const previous_gameweek = self.gameweek_selections[self.active_idx - 1];
        for (previous_gameweek.players) |maybe_player| if (maybe_player) |previous_player| {
            if (player.id == previous_player.id) is_reinsert = true;
        };
    }
    try self.gameweek_selections[self.active_idx].append(player);
    if (is_reinsert) self.gameweek_selections[self.active_idx].addFreeTransfers(1);
    if (options.propagate) {
        for (self.gameweek_selections[self.active_idx + 1 ..]) |*gw_selection| {
            gw_selection.append(player) catch break;
            if (is_reinsert) gw_selection.addFreeTransfers(1);
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

const VisualSettings = @import("config.zig").VisualSettings;

const FixtureTable = @import("components/fixture_table.zig");

const Player = @import("types.zig").Player;

const Chips = @import("types.zig").Chips;
const MAX_FREE_TRANSFERS = @import("types.zig").MAX_FREE_TRANSFERS;
const GAMEWEEK_COUNT = @import("types.zig").GAMEWEEK_COUNT;
const GameweekSelection = @import("gameweek_selection.zig");

const Allocator = std.mem.Allocator;
const std = @import("std");
