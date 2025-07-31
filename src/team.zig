const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Player = struct {
    code: u32,
    web_name: []const u8,
    team_code: u16,
};

const empty_player: Player = .{ .code = 0, .web_name = "<blank>", .team_code = 0 };

pub const Lineup = struct {
    players: [15]Player,

    pub fn init() Lineup {
        return Lineup{
            .players = [_]Player{empty_player} ** 15,
        };
    }

    pub const AppendErrors = error{SelectionFull};

    pub fn appendAny(self: *Lineup, player: Player) AppendErrors!void {
        self.appendStarter(player) catch {
            // if we cannot append as a starter, append as bench
            // return SelectionFull if we cannot append as bench either
            try self.appendBench(player);
        };
    }
    pub fn appendStarter(self: *Lineup, player: Player) AppendErrors!void {
        for (0..11) |i| {
            if (self.players[i].code == 0) {
                self.players[i] = player;
                return;
            }
        }
        return error.SelectionFull;
    }
    pub fn appendBench(self: *Lineup, player: Player) AppendErrors!void {
        for (11..15) |i| {
            if (self.players[i].code == 0) {
                self.players[i] = player;
                return;
            }
        }
        return error.SelectionFull;
    }
};
