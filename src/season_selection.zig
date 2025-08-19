gameweek_selections: [GAMEWEEK_COUNT]GameweekSelection,

active_idx: u8,

const Self = @This();

pub fn init() Self {
    const gameweek_selections = [_]GameweekSelection{GameweekSelection.init()} ** GAMEWEEK_COUNT;
    return .{
        .gameweek_selections = gameweek_selections,
        .active_idx = 0,
    };
}

pub fn incrementIndex(self: *Self, amount: u8) void {
    self.active_idx = std.math.clamp(self.active_idx + amount, 0, GAMEWEEK_COUNT);
}

pub fn decrementIndex(self: *Self, amount: u8) void {
    self.active_idx = std.math.clamp(self.active_idx -| amount, 0, GAMEWEEK_COUNT);
}

pub fn getActiveGameweek(self: Self) GameweekSelection {
    return self.gameweek_selections[self.active_idx];
}

pub fn insertGameweek(self: *Self, gw_selection: GameweekSelection, gw_num: u8) void {
    self.gameweek_selections[gw_num] = gw_selection;
}

const GAMEWEEK_COUNT = @import("types.zig").GAMEWEEK_COUNT;
const GameweekSelection = @import("gameweek_selection.zig");

const std = @import("std");
