const std = @import("std");
const Color = @import("colors.zig").Color;
pub const Teams = enum {
    Arsenal,
    @"Aston Villa",
    Bournemouth,
    Brighton,
    Brentford,
    Burnley,
    Chelsea,
    @"Crystal Palace",
    Everton,
    Fulham,
    Leeds,
    Liverpool,
    @"Man City",
    @"Man Utd",
    Newcastle,
    @"Nott'm Forest",
    Sunderland,
    Spurs,
    @"West Ham",
    Wolves,

    pub fn color(self: Teams) Color {
        return team_colors[@intFromEnum(self)];
    }

    /// Assumes valid team text, panics on missing text.
    pub fn fromString(text: []const u8) Teams {
        return std.meta.stringToEnum(Teams, text) orelse {
            std.debug.panic("Found team name \"{s}\" which is missing from Teams enum.\n", .{text});
        };
    }
};
// TEAM COLORS
const team_colors = [_]Color{
    //  arsenal
    .{ .rgb = .{ 239, 1, 7 } },
    //  aston_villa
    .{ .rgb = .{ 149, 191, 229 } },
    //  bournemouth
    .{ .rgb = .{ 218, 41, 28 } },
    //  brighton
    .{ .rgb = .{ 0, 87, 184 } },
    //  brentford
    .{ .rgb = .{ 210, 0, 0 } },
    //  burnley
    .{ .rgb = .{ 108, 29, 69 } },
    //  chelsea
    .{ .rgb = .{ 3, 70, 148 } },
    //  crystal palace
    .{ .rgb = .{ 27, 69, 143 } },
    //  everton
    .{ .rgb = .{ 39, 68, 136 } },
    //  fulham
    .{ .rgb = .{ 0, 0, 0 } },
    //  leeds
    .{ .rgb = .{ 255, 205, 0 } },
    //  liverpool
    .{ .rgb = .{ 200, 16, 46 } },
    //  manchester city
    .{ .rgb = .{ 108, 171, 221 } },
    //  manchester utd
    .{ .rgb = .{ 218, 41, 28 } },
    //  newcastle
    .{ .rgb = .{ 45, 41, 38 } },
    //  forest
    .{ .rgb = .{ 221, 0, 0 } },
    //  sunderland
    .{ .rgb = .{ 253, 23, 43 } },
    //  spurs
    .{ .rgb = .{ 19, 34, 87 } },
    //  west ham
    .{ .rgb = .{ 122, 38, 58 } },
    //  wolves
    .{ .rgb = .{ 253, 185, 19 } },
};
