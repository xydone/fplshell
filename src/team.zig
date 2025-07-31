const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Player = struct {
    position: Position,
    name: []const u8,
    team_name: []const u8,

    pub const Position = enum {
        gk,
        def,
        mid,
        fwd,
        pub fn fromElementType(element_type: u8) Position {
            return switch (element_type) {
                1 => .gk,
                2 => .def,
                3 => .mid,
                4 => .fwd,
                else => unreachable,
            };
        }
        pub fn toString(position: Position) []const u8 {
            return switch (position) {
                .gk => "Goalkeeper",
                .def => "Defender",
                .mid => "Midfielder",
                .fwd => "Forward",
            };
        }
    };

    fn toString(self: Player) StringPlayer {
        return .{ .name = self.name, .team_name = self.team_name, .position = Position.toString(self.position) };
    }

    pub const StringPlayer = struct {
        position: []const u8,
        name: []const u8,
        team_name: []const u8,
        const empty: StringPlayer = .{ .position = "", .name = "", .team_name = "" };
        fn isEmpty(player: Player) bool {
            return std.mem.eql(u8, player.name, "");
        }
    };
};

pub const Lineup = struct {
    players: [15]?Player,

    pub fn init() Lineup {
        return Lineup{
            .players = [_]?Player{null} ** 15,
        };
    }

    pub fn toString(self: Lineup, buf: *[15]Player.StringPlayer) void {
        for (self.players, 0..) |player, i| {
            if (player) |pl| {
                buf[i] = pl.toString();
            } else buf[i] = Player.StringPlayer.empty;
        }
    }

    pub fn isValid(self: Lineup) bool {
        var gk_count: u4 = 0;
        var def_count: u4 = 0;
        var mid_count: u4 = 0;
        var fwd_count: u4 = 0;
        for (self.players) |player| {
            if (player) |pl| {
                switch (pl.position) {
                    .gk => gk_count += 1,
                    .def => def_count += 1,
                    .mid => mid_count += 1,
                    .fwd => fwd_count += 1,
                }
            }
        }

        // no more than 2 goalkeepers
        if (gk_count > 2) return false;

        // no more than 5 defenders
        if (def_count > 5) return false;

        // no more than 5 midfielders
        if (mid_count > 5) return false;

        // no more than 3 forwards
        if (fwd_count > 3) return false;

        //if all is good...
        return true;
    }

    fn canAppend(self: Lineup, player: Player) bool {
        var player_count: u4 = 0;
        var has_inserted = false;
        var pseudo_lineup = self;
        for (self.players, 0..) |pl, i| {
            if (pl) |_| player_count += 1 else if (!has_inserted) {
                // doing this to avoid an extra loop

                // if an empty slot is found, populate it with the future insert
                pseudo_lineup.players[i] = player;
                has_inserted = true;
            }
        }
        // if we already have a full squad, return false early
        if (player_count == 15) return false;

        // we do not have a full squad, check if its valid
        return pseudo_lineup.isValid();
    }

    pub const AppendErrors = error{SelectionFull};

    pub fn appendAny(self: *Lineup, player: Player) AppendErrors!void {
        // check if we can append a player before appending
        // if not possible exit early
        if (!self.canAppend(player)) return error.SelectionFull;
        self.appendStarter(player) catch {
            // if we cannot append as a starter, append as bench
            // return SelectionFull if we cannot append as bench either
            try self.appendBench(player);
        };
    }
    pub fn appendStarter(self: *Lineup, player: Player) AppendErrors!void {
        for (0..11) |i| {
            if (self.players[i] == null) {
                self.players[i] = player;
                return;
            }
        }
        return error.SelectionFull;
    }
    pub fn appendBench(self: *Lineup, player: Player) AppendErrors!void {
        for (11..15) |i| {
            if (self.players[i] == null) {
                self.players[i] = player;
                return;
            }
        }
        return error.SelectionFull;
    }

    pub fn remove(self: *Lineup, index: u16) void {
        self.players[index] = null;
    }
};
