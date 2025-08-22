const std = @import("std");
const fmt = std.fmt;
const heap = std.heap;
const mem = std.mem;
const meta = std.meta;
const Allocator = std.mem.Allocator;

const vaxis = @import("vaxis");
const Window = vaxis.Window;
const Segment = vaxis.Cell.Segment;
const Table = vaxis.widgets.Table;
const Color = vaxis.Cell.Color;

pub const TableContext = Table.TableContext;
const calcColWidth = Table.calcColWidth;

const Player = @import("../types.zig").Player;
const GameweekSelection = @import("../gameweek_selection.zig");
const Colors = @import("../colors.zig");

const TableCommon = @import("table_common.zig");

table: TableCommon,

const Self = @This();

pub fn init(allocator: Allocator, segment_text: []const u8) !Self {
    const segment = Segment{
        .text = segment_text,
        .style = .{},
    };
    const context = try allocator.create(TableContext);
    context.* = .{
        .active_bg = TableCommon.active_row,
        .active_fg = .{ .rgb = .{ 0, 0, 0 } },
        .row_bg_1 = TableCommon.normal_table,
        .row_bg_2 = TableCommon.normal_table,
        .selected_bg = TableCommon.selected_row,
        .header_names = .{ .custom = &.{ "Position", "Name", "Team", "Price" } },
        .col_indexes = .{ .by_idx = &.{ 0, 1, 2, 3 } },
    };
    const table: TableCommon = .{
        .segment = segment,
        .context = context,
    };
    return Self{
        .table = table,
    };
}

pub fn deinit(self: Self, allocator: Allocator) void {
    self.table.deinit(allocator);
}

// passing in a buf might be a bit annoying, but it saves an allocation soooo
pub fn draw(
    self: *Self,
    allocator: Allocator,
    win: Window,
    table_win: Window,
    lineup: GameweekSelection,
    bufs: struct {
        stats_buf: *[1024]u8,
        transfer_buf: *[1024]u8,
    },
) !void {
    var lineup_buf: [15]Player = undefined;
    lineup.toString(&lineup_buf);
    const list = std.ArrayList(Player).fromOwnedSlice(allocator, &lineup_buf);
    // prepare segment
    const bar = win.child(.{
        .x_off = table_win.x_off,
        .y_off = table_win.y_off - 1,
        .width = table_win.width,
        .height = table_win.height,
    });

    _ = bar.printSegment(self.table.segment.?, .{ .wrap = .word });

    // draw team values
    const team_value_window = win.child(.{
        .x_off = table_win.x_off,
        .y_off = table_win.height + 2,
        .width = table_win.width,
        .height = 1,
    });
    try drawTeamInfo(team_value_window, bufs.stats_buf, lineup);

    // draw transfers

    // here we go!
    const transfer_window = win.child(.{
        .x_off = table_win.x_off,
        .y_off = table_win.height + 3,
        .width = table_win.width,
        .height = 1,
    });
    try drawTransfers(transfer_window, bufs.transfer_buf, lineup);

    try drawInner(allocator, table_win, list, self.table.context);
}

fn drawTeamInfo(window: Window, buf: *[1024]u8, lineup: GameweekSelection) !void {
    const seg: vaxis.Cell.Segment = .{
        .text = try std.fmt.bufPrint(buf, "TV: {d:.1} | ITB: {d:.1} {s}", .{
            lineup.lineup_value,
            lineup.in_the_bank,
            if (lineup.is_valid_formation) "" else "| Invalid formation!",
        }),

        .style = .{ .fg = .default, .bg = .default },
    };

    _ = window.printSegment(seg, .{});
}

fn drawTransfers(window: Window, buf: *[1024]u8, lineup: GameweekSelection) !void {
    const seg: vaxis.Cell.Segment = .{
        .text = try std.fmt.bufPrint(buf, "FT: {} | TM: {} | Cost: {}", .{
            lineup.free_transfers,
            lineup.transfers_made,
            lineup.transfers_made * lineup.hit_value,
        }),

        .style = .{ .fg = .default, .bg = .default },
    };

    _ = window.printSegment(seg, .{});
}

/// draw on the screen (fork of libvaxis's Table.Draw)
fn drawInner(
    allocator: ?mem.Allocator,
    /// The parent Window to draw to.
    win: vaxis.Window,
    data_list: std.ArrayList(Player),
    table_ctx: *TableContext,
) !void {
    const fields = meta.fields(Player);
    const field_indexes = switch (table_ctx.col_indexes) {
        .all => comptime allIdx: {
            var indexes_buf: [fields.len]usize = undefined;
            for (0..fields.len) |idx| indexes_buf[idx] = idx;
            const indexes = indexes_buf;
            break :allIdx indexes[0..];
        },
        .by_idx => |by_idx| by_idx,
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
        if (data_list.items.len > table_win.height -| 1) table_win.height -| 1 else @intCast(data_list.items.len);
    var end = table_ctx.start + max_items;
    if (table_ctx.row + table_ctx.active_y_off >= win.height -| 2)
        end -|= table_ctx.active_y_off;
    if (end > data_list.items.len) end = @intCast(data_list.items.len);
    table_ctx.start = tableStart: {
        if (table_ctx.row == 0)
            break :tableStart 0;
        if (table_ctx.row < table_ctx.start)
            break :tableStart table_ctx.start - (table_ctx.start - table_ctx.row);
        if (table_ctx.row >= data_list.items.len - 1)
            table_ctx.row = @intCast(data_list.items.len - 1);
        if (table_ctx.row >= end)
            break :tableStart table_ctx.start + (table_ctx.row - end + 1);
        break :tableStart table_ctx.start;
    };
    end = table_ctx.start + max_items;
    if (table_ctx.row + table_ctx.active_y_off >= win.height -| 2)
        end -|= table_ctx.active_y_off;
    if (end > data_list.items.len) end = @intCast(data_list.items.len);
    table_ctx.start = @min(table_ctx.start, end);
    table_ctx.active_y_off = 0;
    for (data_list.items[table_ctx.start..end], 0..) |player, row| {
        const row_fg, const row_bg = rowColors: {
            const fg = player.foreground_color orelse .default;
            const bg = player.background_color orelse table_ctx.row_bg_1;

            if (table_ctx.active and table_ctx.start + row == table_ctx.row)
                break :rowColors .{ table_ctx.active_fg, Colors.brighten(bg, 50) };
            if (table_ctx.sel_rows) |rows| {
                if (mem.indexOfScalar(u16, rows, @intCast(table_ctx.start + row)) != null)
                    break :rowColors .{ table_ctx.selected_fg, Colors.darken(bg, 80) };
            }
            break :rowColors .{ fg, bg };
        };

        col_start = 0;
        const item_fields = meta.fields(Player);
        var col_idx: usize = 0;

        const row_y_off: i17 = @intCast(1 + row + table_ctx.active_y_off);
        var row_win = table_win.child(.{
            .x_off = 0,
            .y_off = if (row > 10) row_y_off + 1 else row_y_off,
            .width = table_win.width,
            .height = 1,
        });
        if (table_ctx.start + row == table_ctx.row) {
            table_ctx.active_y_off = if (table_ctx.active_content_fn) |content| try content(&row_win, table_ctx.active_ctx) else 0;
        }

        // draw a bench line
        if (row == 10) {
            const bench_win = table_win.child(.{
                .x_off = 1,
                .y_off = row_y_off + 1, // only increasing by 1 on the line before the bench to make sure this does not offset the entire table
                .width = table_win.width,
                .height = 1,
            });

            const segment = Segment{
                .text = "Bench",
                .style = .{},
            };
            _ = bench_win.printSegment(segment, .{ .wrap = .word });
        }
        for (field_indexes) |f_idx| {
            inline for (item_fields[0..], 0..) |item_field, item_idx| contFields: {
                switch (table_ctx.col_indexes) {
                    .all => {},
                    .by_idx => {
                        if (item_idx != f_idx) break :contFields;
                    },
                }
                defer col_idx += 1;
                const col_width = try calcColWidth(
                    item_idx,
                    headers,
                    table_ctx.col_width,
                    table_win,
                );
                defer col_start += col_width;
                const item = @field(player, item_field.name);
                const ItemT = @TypeOf(item);
                const item_win = row_win.child(.{
                    .x_off = col_start,
                    .y_off = 0,
                    .width = col_width,
                    .height = 1,
                    .border = .{ .where = if (table_ctx.col_borders and col_idx > 0) .left else .none },
                });
                const item_txt = try TableCommon.getCellString(allocator.?, ItemT, item);
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
