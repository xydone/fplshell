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

const Player = @import("../selection.zig").Player;
const Selection = @import("../selection.zig").Selection;

const Colors = @import("../colors.zig");

segment: ?Segment,
context: *TableContext,

const Self = @This();

// Colors
pub const active_row: Color = Colors.light_blue;
pub const selected_row: Color = Colors.black;
pub const selected_table: Color = Colors.black;
pub const normal_table: Color = Colors.black;

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
