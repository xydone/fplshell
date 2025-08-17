buffer: *Buffer,
previous_menu: *Menu,
active_menu: *Menu,

pub fn init(allocator: Allocator, previous_menu: *Menu, active_menu: *Menu) !@This() {
    const buffer = try allocator.create(Buffer);
    buffer.* = Buffer.init(allocator);
    return .{ .buffer = buffer, .previous_menu = previous_menu, .active_menu = active_menu };
}

pub fn deinit(self: *@This(), allocator: Allocator) void {
    self.buffer.deinit();
    allocator.destroy(self.buffer);
}

pub fn setErrorMessage(self: @This(), text: []const u8, current_menu: Menu) !void {
    self.active_menu.* = .error_message;
    self.previous_menu.* = current_menu;
    try self.buffer.insertSliceAtCursor(text);
}

pub fn clearMessage(self: *@This()) void {
    self.buffer.clearRetainingCapacity();
    self.active_menu.* = self.previous_menu.*;
}

pub fn getMessage(self: @This()) []const u8 {
    return self.buffer.firstHalf();
}

const Menu = @import("menus.zig").Menu;
const Buffer = @import("vaxis").widgets.TextInput.Buffer;

const Allocator = std.mem.Allocator;
const std = @import("std");
