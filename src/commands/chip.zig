var COMMANDS = [_][]const u8{"chip"};
var PARAMS = [_]CommandParams{
    .{
        .name = "<?string>",
        .description = "The name of the chip. Empty string remove an existing chip.",
    },
};

pub const description = Command{
    .phrases = &COMMANDS,
    .description = "Activates a chip in the current gameweek.",
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
    season_selections: *SeasonSelection,
    allocator: Allocator,
};

pub const Errors = error{InvalidChip};

fn call(params: Params) Errors!void {
    const it = params.it;
    const season_selections = params.season_selections;

    const chip_name_token = it.next() orelse {
        season_selections.deactivateChip();
        return;
    };
    const chip_names = std.meta.stringToEnum(Chips.Names, chip_name_token) orelse return error.InvalidChip;
    season_selections.activateChip(chip_names.normalise());
}

pub fn handle(cmd: []const u8, params: Params) Errors!void {
    if (shouldCall(cmd)) {
        try call(params);
    }
}

const Chips = @import("../types.zig").Chips;
const SeasonSelection = @import("../season_selection.zig");

const CommandParams = @import("command.zig").Params;
const Command = @import("command.zig");

const Allocator = std.mem.Allocator;
const std = @import("std");
