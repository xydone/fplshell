const std = @import("std");
const vaxis = @import("vaxis");
const Window = vaxis.Window;
const Segment = vaxis.Cell.Segment;
const Table = vaxis.widgets.Table;
const Color = vaxis.Cell.Color;

const Colors = @import("../colors.zig");

const Command = @import("../commands/command.zig");
const FilteredView = @import("../util/filtered_view.zig").FilteredView;
commands: FilteredView(Command, predicate),

const Self = @This();

pub fn init(commands: []Command) Self {
    return Self{
        .commands = .init(commands),
    };
}

fn predicate(cmd: *const Command, text: []const u8) bool {
    // if the text length is <= 1, this means its just the command so exit early
    if (text.len <= 1) return true;
    for (cmd.phrases) |phrase| {
        if (std.mem.startsWith(u8, phrase, text[1..])) return true;
    }
    return false;
}

const bg_color = Colors.dark_blue;

pub fn draw(self: *Self, win: Window, phrase: []const u8) !void {
    var row: i17 = 0;
    defer self.commands.reset();
    while (self.commands.next(phrase)) |command| {
        defer row += 1;
        var x_offset: u16 = 0;

        const bar = win.child(.{
            .x_off = 0,
            .y_off = win.height - (2 + row),
            .width = win.width,
            .height = 1,
        });
        bar.fill(.{ .style = .{ .bg = bg_color } });
        const segment = Segment{
            .text = command.phrases[0], //TODO: better way of doing this
            .style = .{ .bg = bg_color, .fg = Colors.white },
        };
        x_offset += @intCast(segment.text.len + 1);

        _ = bar.printSegment(segment, .{});
        if (command.params) |params| {
            for (params) |param| {
                const param_segment = Segment{
                    .text = param.name,
                    .style = .{ .bg = bg_color, .fg = Colors.white },
                };
                _ = bar.printSegment(param_segment, .{ .col_offset = x_offset });
                x_offset += @intCast(param_segment.text.len + 1);
            }
        }
        if (command.description) |cmd_desc| {
            const command_description = Segment{
                .text = cmd_desc,
                .style = .{ .bg = bg_color, .fg = Colors.gray },
            };
            _ = bar.printSegment(command_description, .{ .col_offset = @intCast(bar.width - cmd_desc.len) });
        }
    }
}
