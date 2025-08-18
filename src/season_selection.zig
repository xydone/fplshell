gameweek_selections: [38]GameweekSelection,

active_idx: u8,

const Self = @This();

pub fn init() Self {
    const gameweek_selections = [_]GameweekSelection{GameweekSelection.init()} ** 38;
    return .{
        .gameweek_selections = gameweek_selections,
        .active_idx = 0,
    };
}

pub fn insertGameweek(self: *Self, gw_selection: GameweekSelection, gw_num: u8) void {
    self.gameweek_selections[gw_num] = gw_selection;
}

const GameweekSelection = @import("gameweek_selection.zig");
