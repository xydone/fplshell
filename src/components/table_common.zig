segment: ?Segment,
context: *TableContext,
visual_settings: VisualSettings,

const Self = @This();

pub fn init(segment_text: ?[]const u8, context: *TableContext, visual_settings: VisualSettings) Self {
    const segment: ?Segment = if (segment_text) |text| .{
        .text = text,
        .style = .{
            .bg = visual_settings.terminal_colors.background,
            .fg = visual_settings.terminal_colors.font,
        },
    } else null;
    return .{
        .segment = segment,
        .context = context,
        .visual_settings = visual_settings,
    };
}

pub fn makeActive(self: *Self) void {
    self.context.active = true;
    self.context.row_bg_1 = self.visual_settings.table_colors.selected;
    self.context.row_bg_2 = self.visual_settings.table_colors.selected;
}

pub fn makeNormal(self: *Self) void {
    self.context.active = false;
    self.context.row_bg_1 = self.visual_settings.table_colors.not_selected;
    self.context.row_bg_2 = self.visual_settings.table_colors.not_selected;
}

pub fn moveDown(self: *Self) void {
    self.context.row +|= 1;
}
pub fn moveUp(self: *Self) void {
    self.context.row -|= 1;
}
pub fn moveTo(self: *Self, to: u16) void {
    self.context.row = to;
}

pub fn deinit(self: Self, allocator: Allocator) void {
    if (self.context.sel_rows) |rows| allocator.free(rows);
    allocator.destroy(self.context);
}

pub fn getCellString(allocator: Allocator, ItemType: anytype, item: anytype) ![]const u8 {
    return switch (ItemType) {
        []const u8 => item,
        [][]const u8, []const []const u8 => try fmt.allocPrint(allocator, "{s}", .{item}),
        else => nonStr: {
            switch (@typeInfo(ItemType)) {
                .@"enum" => break :nonStr @tagName(item),
                .optional => {
                    const opt_item = item orelse break :nonStr "-";
                    switch (@typeInfo(ItemType).optional.child) {
                        []const u8 => break :nonStr opt_item,
                        [][]const u8, []const []const u8 => {
                            break :nonStr try fmt.allocPrint(allocator, "{s}", .{opt_item});
                        },
                        // janky!
                        f16, f32, f64 => {
                            break :nonStr try fmt.allocPrint(allocator, "{d:.1}", .{opt_item});
                        },
                        else => {
                            break :nonStr try fmt.allocPrint(allocator, "{any}", .{opt_item});
                        },
                    }
                },
                else => {
                    break :nonStr try fmt.allocPrint(allocator, "{any}", .{item});
                },
            }
        },
    };
}

const VisualSettings = @import("../config.zig").VisualSettings;

const vaxis = @import("vaxis");
const Window = vaxis.Window;
const Segment = vaxis.Cell.Segment;
const Table = vaxis.widgets.Table;
const Color = vaxis.Cell.Color;

pub const TableContext = Table.TableContext;
const calcColWidth = Table.calcColWidth;

const Player = @import("../types.zig").Player;
const GameweekSelection = @import("../gameweek_selection.zig");

const std = @import("std");
const fmt = std.fmt;
const heap = std.heap;
const mem = std.mem;
const meta = std.meta;
const Allocator = std.mem.Allocator;
