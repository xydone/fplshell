var COMMANDS = [_][]const u8{"load"};
var PARAMS = [_]CommandParams{
    .{
        .name = "<string>",
        .description = "The name of the transfer plan.",
    },
};

const base_path = "data/plans";

pub const description = Command{
    .phrases = &COMMANDS,
    .description = "Loads a transfer plan",
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
    allocator: std.mem.Allocator,
    season_selection: *SeasonSelection,
};

pub const Errors = error{
    EmptyName,
    OOM,
    CannotReadFile,
    CannotParseFile,
};

fn call(params: Params) Errors!LoadResponse {
    const allocator = params.allocator;
    const it = params.it;

    const name = it.next() orelse return error.EmptyName;

    const file_path = std.fmt.allocPrint(allocator, "{s}/{s}.json", .{ base_path, name }) catch return error.OOM;
    defer allocator.free(file_path);

    // 200kb
    const file = std.fs.cwd().readFileAlloc(allocator, file_path, 1024 * 200) catch return error.CannotReadFile;
    defer allocator.free(file);

    const transfer_plan = std.json.parseFromSlice([GAMEWEEK_COUNT]GameweekSelection, allocator, file, .{ .allocate = .alloc_always }) catch return error.CannotParseFile;

    for (transfer_plan.value, 0..) |gameweek, i| {
        params.season_selection.gameweek_selections[i] = gameweek;
    }

    return .{ .transfer_plan = transfer_plan };
}

pub fn handle(cmd: []const u8, params: Params) Errors!?LoadResponse {
    if (shouldCall(cmd)) {
        return try call(params);
    }
    return null;
}

pub const LoadResponse = struct {
    transfer_plan: std.json.Parsed([GAMEWEEK_COUNT]GameweekSelection),

    pub fn deinit(self: LoadResponse) void {
        self.transfer_plan.deinit();
    }
};

const Player = @import("../types.zig").Player;
const GAMEWEEK_COUNT = @import("../types.zig").GAMEWEEK_COUNT;

const GameweekSelection = @import("../gameweek_selection.zig");
const SeasonSelection = @import("../season_selection.zig");
const CommandParams = @import("command.zig").Params;
const Command = @import("command.zig");

const Allocator = std.mem.Allocator;
const std = @import("std");
