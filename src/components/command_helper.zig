commands: FilteredView(Command, predicate),
visual_settings: VisualSettings,

const Self = @This();

pub fn init(commands: []Command, visual_settings: VisualSettings) Self {
    return Self{
        .commands = .init(commands),
        .visual_settings = visual_settings,
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

pub fn draw(self: *Self, win: Window, phrase: []const u8) !void {
    const colors = self.visual_settings.cmd_colors;
    const active_style: vaxis.Cell.Style = .{ .bg = colors.input_background, .fg = colors.active_text };
    const inactive_style: vaxis.Cell.Style = .{ .bg = colors.input_background, .fg = colors.inactive_text };
    const hint_style: vaxis.Cell.Style = .{ .bg = colors.input_background, .fg = colors.hint_text };
    var row: i17 = 0;
    defer self.commands.reset();

    // the reason its a variable and not a constant is because we can change it in the case of an unlimited parameter
    var active_parameter = std.mem.count(u8, phrase, " ");
    while (self.commands.next(phrase)) |command| {
        if (command.params) |params| {
            if (params.len < active_parameter) {
                switch (params[params.len - 1].count) {
                    .limited => |limit| {
                        // we have gone past the limit
                        if (params.len + limit > active_parameter) {
                            continue;
                        }
                    },
                    //NOTE: we dont subtract 1 as we need to ignore the command part and we only have to do this if there are parameters. should be fine.
                    .unlimited => active_parameter = params.len,
                }
            }
        }
        defer row += 1;
        var x_offset: u16 = 0;
        const bar = win.child(.{
            .x_off = 0,
            .y_off = win.height - (2 + row),
            .width = win.width,
            .height = 1,
        });
        bar.fill(.{ .style = .{ .bg = colors.input_background } });

        const segment = Segment{
            .text = command.phrases[0], //TODO: better way of doing this
            .style = if (active_parameter == 0) active_style else inactive_style,
        };

        _ = bar.printSegment(segment, .{ .col_offset = 1 });
        x_offset += @intCast(segment.text.len + 2);

        var param_description: ?[]const u8 = null;

        if (command.params) |params| {
            for (params, 1..) |param, param_idx| {
                const is_active = param_idx == active_parameter;
                if (is_active) {
                    param_description = param.description;
                }

                const param_segment = Segment{
                    .text = param.name,
                    .style = if (is_active) active_style else inactive_style,
                };
                _ = bar.printSegment(param_segment, .{ .col_offset = x_offset });
                x_offset += @intCast(param_segment.text.len + 1);
            }
        }

        if (command.description) |cmd_desc| {
            const command_description = Segment{
                .text = param_description orelse cmd_desc,
                .style = hint_style,
            };
            _ = bar.printSegment(command_description, .{ .col_offset = @intCast(bar.width - 1 - command_description.text.len) });
        }
    }
}

const VisualSettings = @import("../config.zig").VisualSettings;

const Command = @import("../commands/command.zig");
const FilteredView = @import("../util/filtered_view.zig").FilteredView;

const Window = vaxis.Window;
const Segment = vaxis.Cell.Segment;
const Table = vaxis.widgets.Table;
const Color = vaxis.Cell.Color;

const vaxis = @import("vaxis");

const std = @import("std");
