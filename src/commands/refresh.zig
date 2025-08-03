const std = @import("std");
const Table = @import("../components/player_table.zig");

const GetStatic = @import("../fpl.zig").GetStatic;
const GetFixtures = @import("../fpl.zig").GetFixtures;

const COMMANDS = [_][]const u8{ "refresh", "refetch" };

fn shouldCall(cmd: []const u8) bool {
    for (COMMANDS) |c| {
        if (std.mem.eql(u8, c, cmd)) return true;
    }
    return false;
}

pub const Params = struct {
    allocator: std.mem.Allocator,
    static_data: *std.json.Parsed(GetStatic.Response),
    fixtures_data: *std.json.Parsed(GetFixtures.Response),
};

pub const Errors = error{FailedToRefetch};

fn call(params: Params) Errors!void {
    const allocator = params.allocator;
    const static_data = params.static_data;
    const fixtures_data = params.fixtures_data;

    {
        static_data.deinit();
        static_data.* = GetStatic.callRaw(allocator) catch return error.FailedToRefetch;
    }

    {
        fixtures_data.deinit();
        fixtures_data.* = GetFixtures.callRaw(allocator) catch return error.FailedToRefetch;
    }
}

pub fn handle(cmd: []const u8, params: Params) Errors!bool {
    const should_call = shouldCall(cmd);
    if (should_call) {
        try call(params);
    }
    return should_call;
}
