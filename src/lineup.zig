pub const Player = struct {
    position_name: ?[]const u8,
    name: ?[]const u8,
    team_name: ?[]const u8,
    price: ?f32,
    // below are fields that will not be displayed on the table
    team_id: ?u32,
    position: ?Position,
    background_color: ?Color,
    foreground_color: ?Color,

    pub fn fromElementType(element_type: u8) []const u8 {
        return switch (Position.fromElementType(element_type)) {
            .gk => "Goalkeeper",
            .def => "Defender",
            .mid => "Midfielder",
            .fwd => "Forward",
        };
    }

    pub fn getTeamColor(self: Player) !struct { background: Color, foreground: Color } {
        if (self.isEmpty()) return error.EmptyPlayer;
        const bg = Teams.fromString(self.team_name).color();
        return .{
            .background = bg,
            .foreground = Colors.getTextColor(bg),
        };
    }

    /// assumes non-null prices
    pub fn lessThan(_: void, lhs: Player, rhs: Player) bool {
        return lhs.price.? < rhs.price.?;
    }

    /// assumes non-null prices
    pub fn greaterThan(_: void, lhs: Player, rhs: Player) bool {
        return lhs.price.? > rhs.price.?;
    }

    pub const Position = enum {
        gk,
        def,
        mid,
        fwd,
        pub fn fromString(buf: []const u8) Position {
            if (std.mem.eql(u8, "Goalkeeper", buf)) return .gk;
            if (std.mem.eql(u8, "Defender", buf)) return .def;
            if (std.mem.eql(u8, "Midfielder", buf)) return .mid;
            if (std.mem.eql(u8, "Forward", buf)) return .fwd;
            unreachable;
        }

        pub fn fromElementType(element_type: u8) Position {
            return switch (element_type) {
                1 => .gk,
                2 => .def,
                3 => .mid,
                4 => .fwd,
                else => unreachable,
            };
        }
    };
    pub const empty: Player = .{
        .position_name = null,
        .name = null,
        .team_name = null,
        .price = null,
        .team_id = null,
        .background_color = null,
        .foreground_color = null,
        .position = null,
    };
    fn isEmpty(player: Player) bool {
        return player.team_id == 0;
    }
};

pub const Lineup = struct {
    players: [15]?Player,
    lineup_value: f32,
    in_the_bank: f32,
    transfers_made: u8,
    free_transfers: u8,
    hit_value: u8,

    pub fn init() Lineup {
        return Lineup{
            .players = [_]?Player{null} ** 15,
            .lineup_value = 0,
            .in_the_bank = 0,
            .transfers_made = 0,
            .free_transfers = 0,
            .hit_value = 0,
        };
    }

    pub fn toString(self: Lineup, buf: *[15]Player) void {
        for (self.players, 0..) |player, i| {
            if (player) |pl| {
                buf[i] = pl;
            } else buf[i] = Player.empty;
        }
    }

    pub fn isValid(self: Lineup) bool {
        const MAX_PER_TEAM = 3;
        var gk_count: u4 = 0;
        var def_count: u4 = 0;
        var mid_count: u4 = 0;
        var fwd_count: u4 = 0;

        const Team = struct { id: u32, count: u4 = 1 };
        var teams: [20]Team = undefined;
        var team_count: u8 = 0;
        player_loop: for (self.players) |player| {
            if (player) |pl| {
                // do not use this on empty players, pretty please.
                switch (pl.position.?) {
                    .gk => gk_count += 1,
                    .def => def_count += 1,
                    .mid => mid_count += 1,
                    .fwd => fwd_count += 1,
                }
                for (0..team_count) |i| {
                    if (teams[i].id == pl.team_id) {
                        teams[i].count += 1;
                        // early exit if player count exceeds maximum, continue loop if not
                        // continuing the loop manually is done to deal with the teams list
                        if (teams[i].count > MAX_PER_TEAM) return false else continue :player_loop;
                    }
                }
                // if we are here that means a team was not found inside []teams
                teams[team_count] = Team{ .id = pl.team_id.? };
                team_count += 1;
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

    pub const AppendErrors = error{ SelectionFull, MissingFunds };
    pub fn append(self: *Lineup, player: Player) AppendErrors!void {
        // check if we can append a player before appending
        // if not possible exit early
        if (!self.canAppend(player)) return error.SelectionFull;
        inline for (0..15) |i| {
            if (self.players[i] == null) {
                if (self.in_the_bank - player.price.? < 0) return error.MissingFunds;
                self.players[i] = player;
                self.lineup_value += player.price.?;
                self.in_the_bank -= player.price.?;

                return;
            }
        }
        return error.SelectionFull;
    }

    /// Appends will not affect team and itb value
    pub fn appendRaw(self: *Lineup, player: Player) error{SelectionFull}!void {
        inline for (0..15) |i| {
            if (self.players[i] == null) {
                self.players[i] = player;
                return;
            }
        }
        return error.SelectionFull;
    }

    pub fn remove(self: *Lineup, index: u16) void {
        if (self.players[index]) |pl| {
            self.lineup_value -= pl.price.?;
            self.in_the_bank += pl.price.?;
            self.players[index] = null;
        }
    }
};

const Colors = @import("colors.zig");
const Color = Colors.Color;
const Teams = @import("fpl.zig").Teams;

const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const std = @import("std");
