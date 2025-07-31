const std = @import("std");
const Allocator = std.mem.Allocator;

const vaxis = @import("vaxis");
const Window = vaxis.Window;
const Segment = vaxis.Cell.Segment;
const Color = vaxis.Cell.Color;
const Table = vaxis.widgets.Table;
const Context = Table.TableContext;

const Player = @import("../team.zig").Player;
const Lineup = @import("../team.zig").Lineup;

segment: Segment,
context: *Context,

const Self = @This();

// Colors
const active_row: Color = .{ .rgb = .{ 50, 133, 166 } };
const selected_row: Color = .{ .rgb = .{ 0, 0, 0 } };

const selected_table: Color = .{ .rgb = .{ 12, 12, 12 } };
const normal_table: Color = .{ .rgb = .{ 8, 8, 8 } };

pub fn init(allocator: Allocator, segment_text: []const u8) !Self {
    const segment = Segment{
        .text = segment_text,
        .style = .{},
    };
    const context = try allocator.create(Context);
    context.* = .{
        .active_bg = active_row,
        .active_fg = .{ .rgb = .{ 0, 0, 0 } },
        .row_bg_1 = normal_table,
        .row_bg_2 = normal_table,
        .selected_bg = selected_row,
        .header_names = .{ .custom = &.{ "ID", "Name", "Team ID" } },
        .col_indexes = .{ .by_idx = &.{ 0, 1, 2 } },
    };
    return Self{
        .segment = segment,
        .context = context,
    };
}

pub fn makeActive(self: *Self) void {
    self.context.active = true;
    self.context.row_bg_1 = selected_table;
    self.context.row_bg_2 = selected_table;
}

pub fn makeNormal(self: *Self) void {
    self.context.active = false;
    self.context.row_bg_1 = normal_table;
    self.context.row_bg_2 = normal_table;
}

pub fn draw(self: *Self, allocator: Allocator, win: Window, table_win: Window, list: anytype) !void {
    const bar = win.child(.{
        .x_off = table_win.x_off,
        .y_off = table_win.y_off - 1,
        .width = table_win.width,
        .height = table_win.height,
    });

    const aligned = vaxis.widgets.alignment.center(
        bar,
        win.width,
        win.height,
    );
    _ = aligned.printSegment(self.segment, .{ .wrap = .word });

    try Table.drawTable(
        allocator,
        table_win,
        list,
        self.context,
    );
}

pub fn deinit(self: Self, allocator: Allocator) void {
    if (self.context.sel_rows) |rows| allocator.free(rows);
    allocator.destroy(self.context);
}
