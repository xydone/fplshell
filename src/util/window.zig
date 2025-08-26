pub const Options = struct {
    /// location of border, by default all sides
    locations: Locations = all_selected,

    pub const all_selected: Locations = .{ .bottom = true, .top = true, .left = true, .right = true };
};
pub const Context = struct {
    initial_layout: ChildOptions,
    window: Window,
    active_menu: Menu,
    /// the menus which will trigger the drawing of borders
    border_menus: []Menu,
};
pub fn createChild(context: Context, options: Options) vaxis.Window {
    const initial_layout = context.initial_layout;
    const window = context.window;
    const active_menu = context.active_menu;
    const border_menus = context.border_menus;

    var child_window = ChildOptions{
        .x_off = initial_layout.x_off,
        .y_off = initial_layout.y_off,
        .width = initial_layout.width,
        .height = initial_layout.height,
    };
    for (border_menus) |border_menu| blk: {
        if (active_menu == border_menu) {
            child_window.x_off -= 1;
            child_window.y_off -= 1;
            child_window.width = (child_window.width orelse 0) + 2;
            child_window.height = (child_window.height orelse 0) + 2;
            child_window.border = .{
                .where = .{ .other = options.locations },
            };

            // early exit if we've found the menu from the options
            break :blk;
        }
    }
    return window.child(child_window);
}

const Menu = @import("../components/menus.zig").Menu;

const Locations = Window.BorderOptions.Locations;
const ChildOptions = Window.ChildOptions;
const Window = vaxis.Window;
const vaxis = @import("vaxis");
const std = @import("std");
