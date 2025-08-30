team_source: union(enum) {
    id: u32,
    file: ?[]const u8,
},

const config_path = "config/config.zon";
const Self = @This();

const log = std.log.scoped(.config);

pub fn get(allocator: Allocator) !Self {
    return readFileZon(Self, allocator, config_path, 1024 * 5) catch |err| {
        log.err("Could not read the config file!", .{});
        switch (err) {
            error.ExpectedUnion => log.err("NOTE: Check if you have .file and .id uncommented at once!", .{}),
            else => {},
        }
        return err;
    };
}
pub fn deinit(self: Self, allocator: Allocator) void {
    zon.parse.free(allocator, self);
}

pub const TeamFile = struct {
    picks: []Pick,
    picks_last_updated: []const u8,
    transfers: Transfers,
    // chips: []Chip, TODO
    const Pick = struct {
        element: u32,
        position: u32,
        multiplier: u32,
        is_captain: bool,
        is_vice_captain: bool,
        element_type: u32,
        selling_price: u32,
        purchase_price: u32,
    };
    const Transfers = struct {
        cost: u32,
        status: []const u8, //TODO: enum
        limit: ?u32,
        made: u32,
        bank: u32,
        value: u32,
    };

    const config_dir = "config/";
    const default_file_path = config_dir ++ "team.json";

    pub fn get(allocator: Allocator, file_path: ?[]const u8) !std.json.Parsed(TeamFile) {
        const path = if (file_path) |file|
            try std.fmt.allocPrint(allocator, "{s}{s}", .{ config_dir, file })
        else
            default_file_path;

        defer if (file_path) |_| allocator.free(path);
        return readFileJson(TeamFile, allocator, path, 1024 * 5);
    }
};

pub const VisualSettings = struct {
    team_colors: [][3]u8,
    terminal_colors: TerminalColors,
    table_colors: TableColors,
    cmd_colors: CmdColors,

    const TerminalColors = struct {
        background: Color,
        font: Color,
    };

    const TableColors = struct {
        captain: Color,
        vice_captain: Color,
        active_row: Color,
        selected: Color,
        not_selected: Color,

        const default_captain: Color = .{ .rgb = .{ 239, 191, 4 } };
        const default_vice_captain: Color = .{ .rgb = .{ 196, 196, 196 } };
        const default_active_row: Color = .{ .rgb = .{ 50, 133, 166 } };
        const default_selected: Color = .{ .rgb = .{ 0, 0, 0 } };
        const default_not_selected: Color = .{ .rgb = .{ 0, 0, 0 } };
    };

    const CmdColors = struct {
        commands_background: Color,
        input_background: Color,
        active_text: Color,
        inactive_text: Color,
        hint_text: Color,

        const default_commands_background: Color = .{ .rgb = .{ 50, 133, 166 } };
        const default_input_background: Color = .{ .rgb = .{ 24, 95, 122 } };
        const default_active_text: Color = .{ .rgb = .{ 255, 255, 255 } };
        const default_inactive_text: Color = .{ .rgb = .{ 182, 182, 182 } };
        const default_hint_text: Color = .{ .rgb = .{ 182, 182, 182 } };
    };
};

pub const VisualSettingsFile = struct {
    team_colors: [][3]u8,
    terminal_colors: struct {
        background: ?[3]u8 = null,
        font: ?[3]u8 = null,
    },
    table_colors: struct {
        captain: ?[3]u8 = null,
        vice_captain: ?[3]u8 = null,
        active_row: ?[3]u8 = null,
        selected: ?[3]u8 = null,
        not_selected: ?[3]u8 = null,
    },
    cmd_colors: struct {
        commands_background: ?[3]u8 = null,
        input_background: ?[3]u8 = null,
        active_text: ?[3]u8 = null,
        inactive_text: ?[3]u8 = null,
        hint_text: ?[3]u8 = null,
    },

    const path = "config/visual_settings.zon";

    pub fn get(allocator: Allocator) !VisualSettingsFile {
        return try readFileZon(VisualSettingsFile, allocator, path, 1024 * 5);
    }
    pub fn deinit(self: VisualSettingsFile, allocator: Allocator) void {
        zon.parse.free(allocator, self);
    }

    inline fn toColor(opt: ?[3]u8, default: Color) Color {
        return if (opt) |rgb| Color{ .rgb = rgb } else default;
    }
    pub fn toVisualSettings(self: VisualSettingsFile) VisualSettings {
        return .{
            .team_colors = self.team_colors,
            .terminal_colors = .{
                .background = toColor(self.terminal_colors.background, .default),
                .font = toColor(self.terminal_colors.background, .default),
            },
            .table_colors = .{
                .captain = toColor(self.table_colors.captain, VisualSettings.TableColors.default_captain),
                .vice_captain = toColor(self.table_colors.vice_captain, VisualSettings.TableColors.default_vice_captain),
                .active_row = toColor(self.table_colors.active_row, VisualSettings.TableColors.default_active_row),
                .selected = toColor(self.table_colors.selected, VisualSettings.TableColors.default_selected),
                .not_selected = toColor(self.table_colors.not_selected, VisualSettings.TableColors.default_not_selected),
            },
            .cmd_colors = .{
                .commands_background = toColor(self.cmd_colors.commands_background, VisualSettings.CmdColors.default_commands_background),
                .input_background = toColor(self.cmd_colors.input_background, VisualSettings.CmdColors.default_input_background),
                .active_text = toColor(self.cmd_colors.active_text, VisualSettings.CmdColors.default_active_text),
                .inactive_text = toColor(self.cmd_colors.inactive_text, VisualSettings.CmdColors.default_inactive_text),
                .hint_text = toColor(self.cmd_colors.hint_text, VisualSettings.CmdColors.default_hint_text),
            },
        };
    }
};

const ReadFileZonErrors = error{
    CantReadFile,
    ParseZon,
    ExpectedUnion,
};
fn readFileZon(T: type, allocator: Allocator, path: []const u8, max_bytes: u32) ReadFileZonErrors!T {
    const file = std.fs.cwd().readFileAllocOptions(
        allocator,
        path,
        max_bytes,
        null,
        @alignOf(u8),
        0,
    ) catch return error.CantReadFile;
    defer allocator.free(file);

    var status: zon.parse.Status = .{};
    defer status.deinit(allocator);

    return zon.parse.fromSlice(T, allocator, file, &status, .{}) catch {
        var error_it = status.iterateErrors();
        log.debug("Zon parsing error status: {s}", .{status});
        while (error_it.next()) |status_err| {
            if (std.mem.eql(u8, "expected union", status_err.type_check.message)) return error.ExpectedUnion;
        }
        return error.ParseZon;
    };
}

fn readFileJson(T: type, allocator: Allocator, path: []const u8, max_bytes: u32) !std.json.Parsed(T) {
    const file = try std.fs.cwd().readFileAlloc(allocator, path, max_bytes);
    defer allocator.free(file);

    return std.json.parseFromSlice(T, allocator, file, .{
        .allocate = .alloc_always,
        .ignore_unknown_fields = true,
    });
}

const Color = @import("colors.zig").Color;

const zon = std.zon;
const Allocator = std.mem.Allocator;
const std = @import("std");
