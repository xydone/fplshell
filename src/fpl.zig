/// How old does the stored data have to be for us to request it again
/// Defaults to 1hr.
const STALE_AMOUNT = std.time.ns_per_hour * 1;

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
    .{ .rgb = .{ 168, 34, 36 } },
    //  aston_villa
    .{ .rgb = .{ 149, 191, 229 } },
    //  bournemouth
    .{ .rgb = .{ 218, 41, 28 } },
    //  brighton
    .{ .rgb = .{ 14, 100, 196 } },
    //  brentford
    .{ .rgb = .{ 181, 14, 14 } },
    //  burnley
    .{ .rgb = .{ 108, 29, 69 } },
    //  chelsea
    .{ .rgb = .{ 13, 64, 122 } },
    //  crystal palace
    .{ .rgb = .{ 28, 51, 92 } },
    //  everton
    .{ .rgb = .{ 54, 79, 138 } },
    //  fulham
    .{ .rgb = .{ 0, 0, 0 } },
    //  leeds
    .{ .rgb = .{ 255, 205, 0 } },
    //  liverpool
    .{ .rgb = .{ 227, 25, 38 } },
    //  manchester city
    .{ .rgb = .{ 108, 171, 221 } },
    //  manchester utd
    .{ .rgb = .{ 194, 33, 33 } },
    //  newcastle
    .{ .rgb = .{ 45, 41, 38 } },
    //  forest
    .{ .rgb = .{ 133, 17, 17 } },
    //  sunderland
    .{ .rgb = .{ 237, 88, 101 } },
    //  spurs
    .{ .rgb = .{ 181, 185, 199 } },
    //  west ham
    .{ .rgb = .{ 122, 38, 58 } },
    //  wolves
    .{ .rgb = .{ 253, 185, 19 } },
};

pub const GetStatic = struct {
    pub const Response = struct {
        teams: []Team,
        elements: []Element,
        events: []Event,

        const Event = struct {
            is_next: bool,
        };
        const Team = struct {
            id: u32,
            name: []const u8,
            short_name: []const u8,
        };
        const Element = struct {
            id: u32,
            web_name: []const u8,
            team: u16,
            element_type: u8,
            /// stored as an integer, need to do / 10 to get real value
            now_cost: u8,
        };
    };
    const file_path = "data/get_static.json";

    /// Caller must free
    pub fn call(allocator: Allocator) !std.json.Parsed(Response) {
        return isStale(Response, allocator, GetStatic.file_path) catch |err| {
            return switch (err) {
                error.Stale => try callRaw(allocator),
                else => err,
            };
        };
    }

    /// Should only be called directly if you want to prevent stale checks
    pub fn callRaw(allocator: Allocator) !std.json.Parsed(Response) {
        const http = HTTP{
            .url = "https://fantasy.premierleague.com",
            .headers = "",
            .path = "/api/bootstrap-static/",
        };
        const request = try http.get(allocator, Response, .{ .ignore_unknown_fields = true, .allocate = .alloc_always });
        try saveStructToFile(allocator, Response, request.value, GetStatic.file_path);
        return request;
    }
};

pub const GetFixtures = struct {
    pub const Response = []struct {
        id: u32,
        /// gameweek number
        event: u32,
        /// away id
        team_a: u32,
        /// home id
        team_h: u32,
    };
    const file_path = "data/get_fixtures.json";

    pub fn call(allocator: Allocator) !std.json.Parsed(Response) {
        return isStale(Response, allocator, GetFixtures.file_path) catch |err| {
            return switch (err) {
                error.Stale => try callRaw(allocator),
                else => err,
            };
        };
    }

    /// Should only be called directly if you want to prevent stale checks
    pub fn callRaw(allocator: Allocator) !std.json.Parsed(Response) {
        const http = HTTP{
            .url = "https://fantasy.premierleague.com",
            .headers = "",
            .path = "/api/fixtures/",
        };

        const request = try http.get(allocator, Response, .{ .ignore_unknown_fields = true, .allocate = .alloc_always });

        try saveStructToFile(allocator, Response, request.value, GetFixtures.file_path);
        return request;
    }
};

pub const GetEntryHistory = struct {
    pub const Response = struct {
        entry_history: struct {
            event_transfers: u32,
            bank: u32,
            value: u32,
        },
        picks: []struct {
            element: u32,
            position: u8,
            /// 1 - regular player
            /// 2 - captain
            /// 3 - triple captain
            multiplier: u4,
            is_captain: bool,
            is_vice_captain: bool,
            element_type: u32,
        },
    };

    /// Caller must free
    pub fn call(allocator: Allocator, team_id: u32, gameweek: u8) !std.json.Parsed(Response) {
        const path = try std.fmt.allocPrint(allocator, "/api/entry/{d}/event/{d}/picks/", .{ team_id, gameweek });
        defer allocator.free(path);

        const http = HTTP{
            .url = "https://fantasy.premierleague.com",
            .headers = "",
            .path = path,
        };
        const request = try http.get(allocator, Response, .{ .ignore_unknown_fields = true, .allocate = .alloc_always });
        return request;
    }
};

/// Returns error.Stale if stale, and the type T if not stale
/// Caller must free.
fn isStale(
    T: type,
    allocator: Allocator,
    path: []const u8,
) !std.json.Parsed(T) {
    // the reason why this function is not really pure is because I want to save a syscall to read the file again if its not stale and we can safely return

    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        switch (err) {
            error.FileNotFound => return error.Stale,
            else => return err,
        }
    };
    const stat = try file.stat();
    const mtime = stat.mtime;

    if (std.time.nanoTimestamp() > mtime + STALE_AMOUNT) return error.Stale;

    // 100kb
    const contents = try file.readToEndAlloc(allocator, 1024 * 100);
    defer allocator.free(contents);

    return try std.json.parseFromSlice(T, allocator, contents, .{ .allocate = .alloc_always });
}

const saveStructToFile = @import("util/saveStructToFile.zig").saveStructToFile;

const Color = @import("colors.zig").Color;

const HTTP = @import("http.zig");

const Allocator = std.mem.Allocator;
const std = @import("std");
