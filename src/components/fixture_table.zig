const std = @import("std");
const fmt = std.fmt;
const heap = std.heap;
const mem = std.mem;
const meta = std.meta;
const Allocator = std.mem.Allocator;

const TableCommon = @import("table_common.zig");
const vaxis = @import("vaxis");
const Window = vaxis.Window;
const Segment = vaxis.Cell.Segment;
const VaxisTable = vaxis.widgets.Table;
const Color = vaxis.Cell.Color;

const Team = @import("../team.zig");

pub const TableContext = VaxisTable.TableContext;

const calcColWidth = VaxisTable.calcColWidth;

const Colors = @import("../colors.zig");
const active_row = TableCommon.active_row;
const selected_row = TableCommon.selected_row;
const selected_table = TableCommon.selected_table;
const normal_table = TableCommon.normal_table;

table: TableCommon,
header_names: *std.ArrayListUnmanaged([]u8),
start_index: u8,
end_index: u8,

const Self = @This();

pub fn init(allocator: Allocator, first_gw: u8, last_gw: u8) !Self {
    const gameweek_count = last_gw - first_gw + 1;
    const context = try allocator.create(TableContext);

    const header_names = try allocator.create(std.ArrayListUnmanaged([]u8));
    header_names.* = try std.ArrayListUnmanaged([]u8).initCapacity(allocator, gameweek_count);

    for (0..gameweek_count) |i| {
        header_names.appendAssumeCapacity(try std.fmt.allocPrint(allocator, "GW{}", .{i + 1}));
    }

    context.* = .{
        .active_bg = active_row,
        .active_fg = .{ .rgb = .{ 0, 0, 0 } },
        .row_bg_1 = normal_table,
        .row_bg_2 = normal_table,
        .selected_bg = selected_row,
        .header_names = .{ .custom = header_names.items },
    };
    const table = TableCommon{
        .segment = null,
        .context = context,
    };

    return Self{
        .table = table,
        .header_names = header_names,
        .start_index = first_gw,
        .end_index = last_gw,
    };
}

fn updateHeaders(self: *Self, allocator: Allocator, range_start: u8, range_end: u8) !void {
    // free existing headers
    for (0..self.header_names.items.len) |i| {
        allocator.free(self.header_names.items[i]);
    }
    self.header_names.clearRetainingCapacity();
    const range = range_end - range_start + 1;

    for (0..range) |i| {
        try self.header_names.append(allocator, try std.fmt.allocPrint(allocator, "GW{}", .{range_start + i}));
    }
    self.table.context.header_names = .{ .custom = self.header_names.items };
}

const SetRangeErrors = error{InvalidRange};
/// Changes the fixture gameweek range, if there's a null start/end value, it remains the same.
pub fn setRange(self: *Self, allocator: Allocator, start_index: ?u8, end_index: ?u8) SetRangeErrors!void {
    const LOWER_BOUND = 1;
    const UPPER_BOUND = 38;
    const range = (end_index orelse self.end_index) - (start_index orelse self.start_index);
    if (start_index) |idx| {
        if (idx < LOWER_BOUND or idx > UPPER_BOUND - range) return error.InvalidRange;
        self.start_index = idx;
    }
    if (end_index) |idx| {
        self.end_index = idx;
    }

    self.updateHeaders(allocator, self.start_index, self.end_index) catch @panic("OOM");
}

pub fn deinit(self: Self, allocator: Allocator) void {
    self.table.deinit(allocator);

    for (self.header_names.items) |header| {
        allocator.free(header);
    }
    self.header_names.deinit(allocator);
    allocator.destroy(self.header_names);
}
pub fn draw(self: *Self, allocator: Allocator, table_win: Window, fixtures: std.ArrayList(Team)) !void {
    try drawInner(
        allocator,
        table_win,
        fixtures,
        self.table.context,
        self.start_index,
        self.end_index,
    );
}

/// draw on the screen (fork of libvaxis's Table.Draw)
fn drawInner(
    allocator: ?mem.Allocator,
    /// The parent Window to draw to.
    win: vaxis.Window,
    team_list: std.ArrayList(Team),
    table_ctx: *TableContext,
    start_index: u8,
    end_index: u8,
) !void {
    const fields = meta.fields(Team);
    const field_indexes = comptime allIdx: {
        var indexes_buf: [fields.len]usize = undefined;
        for (0..fields.len) |idx| indexes_buf[idx] = idx;
        const indexes = indexes_buf;
        break :allIdx indexes[0..];
    };

    // Headers for the Table
    var hdrs_buf: [fields.len][]const u8 = undefined;
    const headers = hdrs: {
        switch (table_ctx.header_names) {
            .field_names => {
                for (field_indexes) |f_idx| {
                    inline for (fields, 0..) |field, idx| {
                        if (f_idx == idx)
                            hdrs_buf[idx] = field.name;
                    }
                }
                break :hdrs hdrs_buf[0..];
            },
            .custom => |hdrs| break :hdrs hdrs,
        }
    };

    const table_win = win.child(.{
        .y_off = table_ctx.y_off,
        .width = win.width,
        .height = win.height,
    });

    // Headers
    if (table_ctx.col > headers.len - 1) table_ctx.col = @intCast(headers.len - 1);
    var col_start: u16 = 0;
    for (headers[0..], 0..) |hdr_txt, idx| {
        const col_width = try calcColWidth(
            @intCast(idx),
            headers,
            table_ctx.col_width,
            table_win,
        );
        defer col_start += col_width;
        const hdr_fg, const hdr_bg = hdrColors: {
            if (table_ctx.active and idx == table_ctx.col)
                break :hdrColors .{ table_ctx.active_fg, table_ctx.active_bg }
            else if (idx % 2 == 0)
                break :hdrColors .{ .default, table_ctx.hdr_bg_1 }
            else
                break :hdrColors .{ .default, table_ctx.hdr_bg_2 };
        };
        const hdr_win = table_win.child(.{
            .x_off = col_start,
            .y_off = 0,
            .width = col_width,
            .height = 1,
            .border = .{ .where = if (table_ctx.header_borders and idx > 0) .left else .none },
        });
        var hdr = switch (table_ctx.header_align) {
            .left => hdr_win,
            .center => vaxis.widgets.alignment.center(hdr_win, @min(col_width -| 1, hdr_txt.len +| 1), 1),
        };
        hdr_win.fill(.{ .style = .{ .bg = hdr_bg } });
        var seg = [_]vaxis.Cell.Segment{.{
            .text = if (hdr_txt.len > col_width and allocator != null) try fmt.allocPrint(allocator.?, "{s}...", .{hdr_txt[0..(col_width -| 4)]}) else hdr_txt,
            .style = .{
                .fg = hdr_fg,
                .bg = hdr_bg,
                .bold = true,
                .ul_style = if (idx == table_ctx.col) .single else .dotted,
            },
        }};
        _ = hdr.print(seg[0..], .{ .wrap = .word });
    }

    // Rows
    if (table_ctx.active_content_fn == null) table_ctx.active_y_off = 0;
    const max_items: u16 =
        if (team_list.items.len > table_win.height -| 1) table_win.height -| 1 else @intCast(team_list.items.len);
    var end = table_ctx.start + max_items;
    if (table_ctx.row + table_ctx.active_y_off >= win.height -| 2)
        end -|= table_ctx.active_y_off;
    if (end > team_list.items.len) end = @intCast(team_list.items.len);
    table_ctx.start = tableStart: {
        if (table_ctx.row == 0)
            break :tableStart 0;
        if (table_ctx.row < table_ctx.start)
            break :tableStart table_ctx.start - (table_ctx.start - table_ctx.row);
        if (table_ctx.row >= team_list.items.len - 1)
            table_ctx.row = @intCast(team_list.items.len - 1);
        if (table_ctx.row >= end)
            break :tableStart table_ctx.start + (table_ctx.row - end + 1);
        break :tableStart table_ctx.start;
    };
    end = table_ctx.start + max_items;
    if (table_ctx.row + table_ctx.active_y_off >= win.height -| 2)
        end -|= table_ctx.active_y_off;
    if (end > team_list.items.len) end = @intCast(team_list.items.len);
    table_ctx.start = @min(table_ctx.start, end);
    table_ctx.active_y_off = 0;
    for (team_list.items[table_ctx.start..end], 0..) |fix, row| {
        const row_fg, const row_bg = rowColors: {
            const fg = .default;
            const bg = table_ctx.row_bg_1;

            if (table_ctx.active and table_ctx.start + row == table_ctx.row)
                break :rowColors .{ table_ctx.active_fg, Colors.brighten(bg, 50) };
            if (table_ctx.sel_rows) |rows| {
                if (mem.indexOfScalar(u16, rows, @intCast(table_ctx.start + row)) != null)
                    break :rowColors .{ table_ctx.selected_fg, Colors.darken(bg, 80) };
            }
            break :rowColors .{ fg, bg };
        };

        col_start = 0;
        var col_idx: usize = 0;

        const row_y_off: i17 = @intCast(1 + row + table_ctx.active_y_off);
        var row_win = table_win.child(.{
            .x_off = 0,
            // add an empty space where the "Bench" would be on the lineup
            .y_off = if (row > 10) row_y_off + 1 else row_y_off,
            .width = table_win.width,
            .height = 1,
        });
        if (table_ctx.start + row == table_ctx.row) {
            table_ctx.active_y_off = if (table_ctx.active_content_fn) |content| try content(&row_win, table_ctx.active_ctx) else 0;
        }
        if (fix.opponents) |opponents| {
            for (opponents[start_index - 1 .. end_index], 0..) |opponent, item_idx| {
                defer col_idx += 1;
                const col_width = try calcColWidth(@intCast(item_idx), headers, table_ctx.col_width, table_win);
                defer col_start += col_width;

                const item_win = row_win.child(.{
                    .x_off = col_start,
                    .y_off = 0,
                    .width = col_width,
                    .height = 1,
                    .border = .{ .where = if (table_ctx.col_borders and col_idx > 0) .left else .none },
                });
                const item_txt = try opponent.toString(allocator.?);
                item_win.fill(.{ .style = .{ .bg = row_bg } });
                const item_align_win = itemAlignWin: {
                    const col_align = switch (table_ctx.col_align) {
                        .all => |all| all,
                        .by_idx => |aligns| aligns[col_idx],
                    };
                    break :itemAlignWin switch (col_align) {
                        .left => item_win,
                        .center => center: {
                            const center = vaxis.widgets.alignment.center(item_win, @min(col_width -| 1, item_txt.len +| 1), 1);
                            center.fill(.{ .style = .{ .bg = row_bg } });
                            break :center center;
                        },
                    };
                };

                var seg = [_]vaxis.Cell.Segment{.{
                    .text = if (item_txt.len > col_width and allocator != null) try fmt.allocPrint(allocator.?, "{s}...", .{item_txt[0..(col_width -| 4)]}) else item_txt,
                    .style = .{ .fg = row_fg, .bg = row_bg },
                }};
                _ = item_align_win.print(seg[0..], .{ .wrap = .word, .col_offset = table_ctx.cell_x_off });
            }
        }
    }
}
