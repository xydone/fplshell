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
    var it = std.mem.tokenizeSequence(u8, text, " ");
    // if the command is null, that means there are no characters, so do not show any hints
    const command = it.next() orelse return false;
    // if the text length is <= 1, this means its just the command so exit early
    if (command.len <= 1) return true;
    for (cmd.phrases) |phrase| {
        if (std.mem.startsWith(u8, phrase, command[1..])) return true;
    }
    return false;
}

const bg_color = Colors.dark_blue;

pub fn draw(self: *Self, win: Window, phrase: []const u8) !void {
    const active_style: vaxis.Cell.Style = .{ .bg = bg_color, .fg = Colors.white };
    const inactive_style: vaxis.Cell.Style = .{ .bg = bg_color, .fg = Colors.light_gray };
    const hint_style: vaxis.Cell.Style = .{ .bg = bg_color, .fg = Colors.light_gray };
    var row: i17 = 0;
    defer self.commands.reset();

    const active_parameter = std.mem.count(u8, phrase, " ");
    while (self.commands.next(phrase)) |command| {
        if (command.params) |params| {
            if (params.len < active_parameter) continue;
        }
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
            .style = if (active_parameter == 0) active_style else inactive_style,
        };
        x_offset += @intCast(segment.text.len + 1);

        _ = bar.printSegment(segment, .{});
        if (command.params) |params| {
            for (params, 1..) |param, param_idx| {
                const param_segment = Segment{
                    .text = param.name,
                    .style = if (param_idx == active_parameter) active_style else inactive_style,
                };
                _ = bar.printSegment(param_segment, .{ .col_offset = x_offset });
                x_offset += @intCast(param_segment.text.len + 1);
            }
        }

        if (command.description) |cmd_desc| {
            const command_description = Segment{
                .text = cmd_desc,
                .style = hint_style,
            };
            _ = bar.printSegment(command_description, .{ .col_offset = @intCast(bar.width - cmd_desc.len) });
        }
    }
}
