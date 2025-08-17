const std = @import("std");
const Allocator = std.mem.Allocator;

const Team = @This();

opponents: ?[]Match,
name: ?[]const u8,

pub const Match = struct {
    opponent_name: []const u8,
    opponent_short: []const u8,
    venue: enum { home, away },
    opponent_id: u32,
    pub fn toString(self: Match, allocator: Allocator) ![]u8 {
        return try std.fmt.allocPrint(allocator, "{s} ({s})", .{ self.opponent_short, switch (self.venue) {
            .home => "H",
            .away => "A",
        } });
    }
};

const empty = Team{
    .name = null,
    .opponents = null,
    // .first_gw = null,
    // .second_gw = null,
    // .third_gw = null,
};

pub const TeamList = struct {
    teams: [15]?Team,
    pub fn init() TeamList {
        return TeamList{
            .teams = [_]?Team{null} ** 15,
        };
    }
    pub fn toString(self: TeamList, buf: *[15]Team) void {
        for (self.teams, 0..) |team, i| {
            if (team) |t| {
                buf[i] = t;
            } else buf[i] = Team.empty;
        }
    }

    pub const AppendErrors = error{SelectionFull};
    pub fn appendAny(self: *TeamList, team: Team) AppendErrors!void {
        self.appendStarter(team) catch {
            // if we cannot append as a starter, append as bench
            // return SelectionFull if we cannot append as bench either
            try self.appendBench(team);
        };
    }

    /// Does not check if lineup is valid.
    pub fn appendStarter(self: *TeamList, team: Team) AppendErrors!void {
        for (0..11) |i| {
            if (self.teams[i] == null) {
                self.teams[i] = team;
                return;
            }
        }
        return error.SelectionFull;
    }

    /// Does not check if lineup is valid.
    pub fn appendBench(self: *TeamList, team: Team) AppendErrors!void {
        for (11..15) |i| {
            if (self.teams[i] == null) {
                self.teams[i] = team;
                return;
            }
        }
        return error.SelectionFull;
    }

    pub fn remove(self: *TeamList, index: u16) void {
        self.teams[index] = null;
    }
};
