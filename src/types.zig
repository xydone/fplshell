pub const GAMEWEEK_COUNT = 38;
pub const MAX_FREE_TRANSFERS = 5;
pub const HIT_VALUE = 4;

pub const Chips = enum {
    wildcard,
    free_hit,
    bench_boost,
    triple_captain,

    /// Includes all the chip names from the root enum and aliases
    pub const Names = enum {
        wildcard,
        wc,

        free_hit,
        fh,

        bench_boost,
        bb,

        triple_captain,
        tc,

        pub inline fn normalise(self: @This()) Chips {
            return switch (self) {
                inline .wildcard, .free_hit, .bench_boost, .triple_captain => |chip| @field(Chips, @tagName(chip)),
                .wc => Chips.wildcard,
                .fh => Chips.free_hit,
                .bb => Chips.bench_boost,
                .tc => Chips.triple_captain,
            };
        }
    };
};

pub const Player = struct {
    position_name: ?[]const u8,
    name: ?[]const u8,
    team_name: ?[]const u8,
    price: ?f32,
    // below are fields that will not be displayed on the table
    id: ?u32,
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
        .id = null,
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

const Teams = @import("fpl.zig").Teams;
const Color = @import("colors.zig").Color;

const std = @import("std");
