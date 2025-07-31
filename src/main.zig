const std = @import("std");
const HTTP = @import("http.zig");
const Player = @import("team.zig").Player;

const vaxis = @import("vaxis");
const TextInput = vaxis.widgets.TextInput;
const Key = vaxis.Key;

const Table = @import("components/table.zig");

const Lineup = @import("team.zig").Lineup;

const APIResponse = struct {
    teams: []Team,
    elements: []Element,

    const Team = struct {
        code: u32,
        name: []const u8,
    };
    const Element = struct {
        code: u32,
        web_name: []const u8,
        team_code: u16,
        element_type: u8,
    };
};

const State = enum {
    active,
    typing,
};

pub fn main() !void {
    var allocator_instance = std.heap.GeneralPurposeAllocator(.{
        .stack_trace_frames = if (std.debug.sys_can_stack_trace) 10 else 0,
        .resize_stack_traces = true,
    }).init;
    defer _ = allocator_instance.deinit();

    const allocator = allocator_instance.allocator();

    const http = HTTP{
        .url = "https://fantasy.premierleague.com",
        .headers = "",
        .path = "/api/bootstrap-static/",
    };

    const resp = try http.get(allocator, APIResponse, .{ .ignore_unknown_fields = true, .allocate = .alloc_always });
    defer resp.deinit();

    var player_map = std.StringHashMapUnmanaged(Player).empty;
    defer player_map.deinit(allocator);

    var team_map = std.AutoHashMapUnmanaged(u32, []const u8).empty;
    defer team_map.deinit(allocator);

    for (resp.value.teams) |team| {
        try team_map.put(allocator, team.code, team.name);
    }

    for (resp.value.elements) |element| {
        const player = Player{
            .name = element.web_name,
            .position = Player.Position.fromElementType(element.element_type),
            .team_name = team_map.get(element.team_code) orelse std.debug.panic("Team code {d} not found in team map!", .{element.team_code}),
        };
        try player_map.put(allocator, player.name, player);
    }

    // Terminal stuff

    var tty = try vaxis.Tty.init();
    defer tty.deinit();
    var tty_buf_writer = tty.bufferedWriter();
    defer tty_buf_writer.flush() catch {};

    var vx = try vaxis.init(allocator, .{});
    defer vx.deinit(allocator, tty.anyWriter());

    var loop: vaxis.Loop(Event) = .{
        .tty = &tty,
        .vaxis = &vx,
    };
    try loop.init();

    try loop.start();
    defer loop.stop();

    try vx.enterAltScreen(tty.anyWriter());

    var text_input = TextInput.init(allocator, &vx.unicode);
    defer text_input.deinit();

    try vx.queryTerminal(tty.anyWriter(), 1 * std.time.ns_per_s);

    var filtered_players = std.ArrayList(Player).init(allocator);
    defer filtered_players.deinit();

    var event_arena = std.heap.ArenaAllocator.init(allocator);
    defer event_arena.deinit();

    var state: State = .typing;

    var filtered = try Table.init(allocator, "Select a player");
    defer filtered.deinit(allocator);
    filtered.makeActive();

    var selected = try Table.init(allocator, "Selected players");
    defer selected.deinit(allocator);

    const Tables = enum { left, right };
    var active_table: Tables = .left;

    var lineup: Lineup = .init();

    while (true) {
        defer _ = event_arena.reset(.retain_capacity);
        defer tty_buf_writer.flush() catch {};

        const event_alloc = event_arena.allocator();
        const event = loop.nextEvent();

        event: switch (event) {
            .key_press => |key| {
                if (key.matches('c', .{ .ctrl = true })) {
                    break;
                }
                // row navigation
                if (key.matches(Key.up, .{})) {
                    switch (active_table) {
                        .left => {
                            filtered.context.row -|= 1;
                        },
                        .right => {
                            selected.context.row -|= 1;
                        },
                    }
                } else if (key.matches(Key.down, .{})) {
                    switch (active_table) {
                        .left => {
                            filtered.context.row +|= 1;
                        },
                        .right => {
                            selected.context.row +|= 1;
                        },
                    }
                }

                switch (state) {
                    .typing => {
                        // go to active state
                        if (key.matches(Key.tab, .{})) {
                            state = .active;
                        } else if (key.matches(Key.enter, .{})) {
                            // append player
                            lineup.appendAny(filtered_players.items[filtered.context.row]) catch {
                                //TODO: signify selection full somehow?
                            };
                        } else {
                            try text_input.update(.{ .key_press = key });
                            filtered.context.row = 0;
                            const buf = text_input.buf.firstHalf();

                            // if nothing has been entered, just continue early
                            filtered_players.clearRetainingCapacity();
                            if (buf.len == 0) break :event;

                            const input = try std.ascii.allocLowerString(event_alloc, text_input.buf.firstHalf());
                            var it = player_map.iterator();
                            while (it.next()) |entry| {
                                const entry_name = try std.ascii.allocLowerString(event_alloc, entry.key_ptr.*);

                                if (std.mem.containsAtLeast(u8, entry_name, 1, input)) {
                                    try filtered_players.append(entry.value_ptr.*);
                                }
                            }
                        }
                    },
                    .active => {
                        // go back to typing state
                        if (key.matches(Key.tab, .{})) {
                            state = .typing;
                        }

                        // table navigation
                        switch (active_table) {
                            .left => {
                                if (key.matches(Key.right, .{})) {
                                    active_table = .right;
                                    selected.makeActive();
                                    filtered.makeNormal();
                                } else if (key.matches(Key.enter, .{})) {
                                    // append player
                                    lineup.appendAny(filtered_players.items[filtered.context.row]) catch {
                                        //TODO: signify selection full somehow?
                                    };
                                }
                            },
                            .right => {
                                if (key.matches(Key.left, .{})) {
                                    active_table = .left;
                                    filtered.makeActive();
                                    selected.makeNormal();
                                } else if (key.matches(Key.enter, .{})) {
                                    // append player
                                    lineup.remove(selected.context.row);
                                }
                            },
                        }
                    },
                }
            },

            .winsize => |ws| try vx.resize(allocator, tty.anyWriter(), ws),
            else => {},
        }

        const win = vx.window();

        win.clear();

        const style: vaxis.Style = .{
            .fg = .{ .rgb = .{ 64, 128, 255 } },
        };

        const child = win.child(.{
            .x_off = win.width / 2 - 20,
            .y_off = 0,
            .width = 40,
            .height = 3,
            .border = .{
                .where = .all,
                .style = style,
            },
        });

        text_input.draw(child);

        // left table
        const filtered_win = win.child(.{
            .x_off = 1,
            .y_off = 5,
            .width = win.width / 2,
            .height = win.height,
        });

        try filtered.draw(event_alloc, win, filtered_win, filtered_players);
        // right table
        const selected_win = win.child(.{
            .x_off = filtered_win.width + filtered_win.x_off + 2,
            .y_off = filtered_win.y_off,
            .width = win.width / 2,
            .height = win.height,
        });
        var buf: [15]Player.StringPlayer = undefined;
        lineup.toString(&buf);
        const players = std.ArrayList(Player.StringPlayer).fromOwnedSlice(allocator, &buf);

        try selected.draw(event_alloc, win, selected_win, players);

        const tty_writer = tty_buf_writer.writer().any();

        try vx.render(tty_writer);
    }
}

const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
    focus_in,
};
