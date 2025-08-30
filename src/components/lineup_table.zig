table: TableCommon,

const Self = @This();

pub fn init(allocator: Allocator, visual_settings: VisualSettings, segment_text: []const u8) !Self {
    const context = try allocator.create(TableContext);
    context.* = .{
        .active_bg = visual_settings.table_colors.active_row,
        .active_fg = .{ .rgb = .{ 0, 0, 0 } },
        .row_bg_1 = visual_settings.table_colors.not_selected,
        .row_bg_2 = visual_settings.table_colors.not_selected,
        .selected_bg = visual_settings.table_colors.selected,
        .header_names = .{ .custom = &.{ "Position", "Name", "Team", "Price" } },
        .col_indexes = .{ .by_idx = &.{ 0, 1, 2, 3 } },
    };
    const table: TableCommon = .init(segment_text, context, visual_settings);
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
    gameweek_selection: GameweekSelection,
    bufs: struct {
        stats_buf: *[1024]u8,
        transfer_buf: *[1024]u8,
    },
) !void {
    var lineup_buf: [15]Player = undefined;
    gameweek_selection.toString(&lineup_buf);
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
    const text_offset: i17 = if (gameweek_selection.chip_active != .bench_boost) 1 else 0;
    const team_value_window = win.child(.{
        .x_off = table_win.x_off,
        .y_off = table_win.height + text_offset + 1,
        .width = table_win.width,
        .height = 1,
    });

    try self.drawTeamInfo(
        team_value_window,
        bufs.stats_buf,
        gameweek_selection,
    );

    // draw transfers

    // here we go!
    const transfer_window = win.child(.{
        .x_off = table_win.x_off,
        .y_off = table_win.height + text_offset + 2,
        .width = table_win.width,
        .height = 1,
    });
    try self.drawTransfers(
        transfer_window,
        bufs.transfer_buf,
        gameweek_selection,
    );

    try self.drawInner(
        allocator,
        table_win,
        list,
        gameweek_selection,
    );
}

fn drawTeamInfo(self: Self, window: Window, buf: *[1024]u8, lineup: GameweekSelection) !void {
    const seg: vaxis.Cell.Segment = .{
        .text = try std.fmt.bufPrint(buf, "TV: {d:.1} | ITB: {d:.1} {s}", .{
            lineup.lineup_value,
            lineup.in_the_bank,
            if (lineup.is_valid_formation) "" else "| Invalid formation!",
        }),

        .style = .{
            .fg = self.table.visual_settings.terminal_colors.font,
            .bg = self.table.visual_settings.terminal_colors.background,
        },
    };

    _ = window.printSegment(seg, .{});
}

fn drawTransfers(self: Self, window: Window, buf: *[1024]u8, lineup: GameweekSelection) !void {
    const seg: vaxis.Cell.Segment = .{
        .text = try std.fmt.bufPrint(buf, "FT: {s} | TM: {} | Cost: {} {s}", .{
            blk: {
                if (lineup.chip_active) |chip| {
                    switch (chip) {
                        .wildcard, .free_hit => break :blk "∞",
                        else => {},
                    }
                }
                var ft_value_buf: [3]u8 = undefined;
                break :blk try std.fmt.bufPrint(&ft_value_buf, "{}", .{lineup.free_transfers});
            },
            lineup.transfers_made,
            lineup.amount_of_hits * HIT_VALUE,
            if (lineup.chip_active) |chip|
            blk: {
                break :blk switch (chip) {
                    .wildcard => "| Wildcard active!",
                    .free_hit => "| Free hit active!",
                    .triple_captain => "| Triple captain active!",
                    .bench_boost => "| Bench boost active!",
                };
            } else "",
        }),

        .style = .{
            .fg = self.table.visual_settings.terminal_colors.font,
            .bg = self.table.visual_settings.terminal_colors.background,
        },
    };

    _ = window.printSegment(seg, .{});
}

/// draw on the screen (fork of libvaxis's Table.Draw)
fn drawInner(
    self: Self,
    allocator: ?mem.Allocator,
    /// The parent Window to draw to.
    win: vaxis.Window,
    data_list: std.ArrayList(Player),
    gameweek_selection: GameweekSelection,
) !void {
    const fields = meta.fields(Player);
    const field_indexes = switch (self.table.context.col_indexes) {
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
        switch (self.table.context.header_names) {
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
        .y_off = self.table.context.y_off,
        .width = win.width,
        .height = win.height,
    });

    // Headers
    if (self.table.context.col > headers.len - 1) self.table.context.col = @intCast(headers.len - 1);
    var col_start: u16 = 0;
    for (headers[0..], 0..) |hdr_txt, idx| {
        const col_width = try calcColWidth(
            @intCast(idx),
            headers,
            self.table.context.col_width,
            table_win,
        );
        defer col_start += col_width;
        const hdr_fg, const hdr_bg = hdrColors: {
            if (self.table.context.active and idx == self.table.context.col)
                break :hdrColors .{ self.table.context.active_fg, self.table.context.active_bg }
            else if (idx % 2 == 0)
                break :hdrColors .{ .default, self.table.context.hdr_bg_1 }
            else
                break :hdrColors .{ .default, self.table.context.hdr_bg_2 };
        };
        const hdr_win = table_win.child(.{
            .x_off = col_start,
            .y_off = 0,
            .width = col_width,
            .height = 1,
            .border = .{
                .where = if (self.table.context.header_borders and idx > 0) .left else .none,
            },
        });
        var hdr = switch (self.table.context.header_align) {
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
                .ul_style = if (idx == self.table.context.col) .single else .dotted,
            },
        }};
        _ = hdr.print(seg[0..], .{ .wrap = .word });
    }

    // Rows
    if (self.table.context.active_content_fn == null) self.table.context.active_y_off = 0;
    const max_items: u16 =
        if (data_list.items.len > table_win.height -| 1) table_win.height -| 1 else @intCast(data_list.items.len);
    var end = self.table.context.start + max_items;
    if (self.table.context.row + self.table.context.active_y_off >= win.height -| 2)
        end -|= self.table.context.active_y_off;
    if (end > data_list.items.len) end = @intCast(data_list.items.len);
    self.table.context.start = tableStart: {
        if (self.table.context.row == 0)
            break :tableStart 0;
        if (self.table.context.row < self.table.context.start)
            break :tableStart self.table.context.start - (self.table.context.start - self.table.context.row);
        if (self.table.context.row >= data_list.items.len - 1)
            self.table.context.row = @intCast(data_list.items.len - 1);
        if (self.table.context.row >= end)
            break :tableStart self.table.context.start + (self.table.context.row - end + 1);
        break :tableStart self.table.context.start;
    };
    end = self.table.context.start + max_items;
    if (self.table.context.row + self.table.context.active_y_off >= win.height -| 2)
        end -|= self.table.context.active_y_off;
    if (end > data_list.items.len) end = @intCast(data_list.items.len);
    self.table.context.start = @min(self.table.context.start, end);
    self.table.context.active_y_off = 0;
    for (data_list.items[self.table.context.start..end], 0..) |player, row| {
        const is_captain = if (gameweek_selection.captain_idx) |idx| idx == row else false;
        const is_vice_captain = if (gameweek_selection.vice_captain_idx) |idx| idx == row else false;
        const row_fg, const row_bg = rowColors: {
            const fg = player.foreground_color orelse .default;
            const bg = player.background_color orelse self.table.context.row_bg_1;

            if (self.table.context.active and self.table.context.start + row == self.table.context.row)
                break :rowColors .{ self.table.context.active_fg, Colors.brighten(bg, 50) };
            if (self.table.context.sel_rows) |rows| {
                if (mem.indexOfScalar(u16, rows, @intCast(self.table.context.start + row)) != null)
                    break :rowColors .{ self.table.context.selected_fg, Colors.darken(bg, 80) };
            }
            break :rowColors .{ fg, bg };
        };

        col_start = if (is_captain or is_vice_captain) 1 else 0;
        const item_fields = meta.fields(Player);
        var col_idx: usize = 0;

        const row_y_off: i17 = blk: {
            const y_off: i17 = @intCast(1 + row + self.table.context.active_y_off);
            if (row > 10) {
                if (gameweek_selection.chip_active != .bench_boost) break :blk y_off + 1 else break :blk y_off;
            } else break :blk y_off;
        };
        var row_win = table_win.child(.{
            .x_off = 0,
            .y_off = row_y_off,
            .width = table_win.width,
            .height = 1,
        });
        if (self.table.context.start + row == self.table.context.row) {
            self.table.context.active_y_off = if (self.table.context.active_content_fn) |content| try content(&row_win, self.table.context.active_ctx) else 0;
        }

        // draw a bench line
        if (row == 10 and gameweek_selection.chip_active != .bench_boost) {
            const bench_win = table_win.child(.{
                .x_off = 1,
                .y_off = row_y_off + 1, // only increasing by 1 on the line before the bench to make sure this does not offset the entire table
                .width = table_win.width,
                .height = 1,
            });

            const segment = Segment{
                .text = "Bench",
                .style = .{ .bg = self.table.visual_settings.terminal_colors.background },
            };
            _ = bench_win.printSegment(segment, .{ .wrap = .word });
        }
        // draw a captaincy square
        if (is_captain) {
            const captain_window = row_win.child(.{
                .x_off = 0,
                .y_off = 0,
                .width = 1,
                .height = 1,
            });
            captain_window.fill(.{ .style = .{ .bg = self.table.visual_settings.table_colors.captain } });
        } else if (is_vice_captain) {
            const vice_captain_window = row_win.child(.{
                .x_off = 0,
                .y_off = 0,
                .width = 1,
                .height = 1,
            });
            vice_captain_window.fill(.{ .style = .{ .bg = self.table.visual_settings.table_colors.vice_captain } });
        }
        for (field_indexes) |f_idx| {
            inline for (item_fields[0..], 0..) |item_field, item_idx| contFields: {
                switch (self.table.context.col_indexes) {
                    .all => {},
                    .by_idx => {
                        if (item_idx != f_idx) break :contFields;
                    },
                }
                defer col_idx += 1;
                const col_width = try calcColWidth(
                    item_idx,
                    headers,
                    self.table.context.col_width,
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
                    .border = .{
                        .where = if (self.table.context.col_borders and col_idx > 0) .left else .none,
                    },
                });
                const item_txt = try TableCommon.getCellString(allocator.?, ItemT, item);
                item_win.fill(.{ .style = .{ .bg = row_bg } });
                const item_align_win = itemAlignWin: {
                    const col_align = switch (self.table.context.col_align) {
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

                const seg: Segment = .{
                    .text = if (item_txt.len > col_width and allocator != null) try fmt.allocPrint(allocator.?, "{s}...", .{item_txt[0..(col_width -| 4)]}) else item_txt,
                    .style = .{ .fg = row_fg, .bg = row_bg },
                };
                _ = item_align_win.printSegment(seg, .{ .wrap = .word, .col_offset = self.table.context.cell_x_off });
            }
        }
    }
}

const VisualSettings = @import("../config.zig").VisualSettings;

const vaxis = @import("vaxis");
const Window = vaxis.Window;
const Segment = vaxis.Cell.Segment;
const Table = vaxis.widgets.Table;
const Color = vaxis.Cell.Color;

pub const TableContext = Table.TableContext;
const calcColWidth = Table.calcColWidth;

const Chips = @import("../types.zig").Chips;
const HIT_VALUE = @import("../types.zig").HIT_VALUE;
const Player = @import("../types.zig").Player;
const GameweekSelection = @import("../gameweek_selection.zig");
const Colors = @import("../colors.zig");

const TableCommon = @import("table_common.zig");

const fmt = std.fmt;
const heap = std.heap;
const mem = std.mem;
const meta = std.meta;
const Allocator = std.mem.Allocator;
const std = @import("std");
