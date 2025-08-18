pub const GAMEWEEK_COUNT = 38;

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

const Color = Colors.Color;
const Teams = @import("fpl.zig").Teams;
const Colors = @import("colors.zig");

const std = @import("std");
