const std = @import("std");
const HTTP = @import("http.zig");
const Player = @import("lineup.zig").Player;

const vaxis = @import("vaxis");
const TextInput = vaxis.widgets.TextInput;
const Key = vaxis.Key;

const Table = @import("components/table.zig");
const TableContext = Table.TableContext;

const Lineup = @import("lineup.zig").Lineup;

const Colors = @import("colors.zig");
const Teams = @import("fpl.zig").Teams;

const Go = @import("commands/go.zig");
const Search = @import("commands/search.zig");
const Reset = @import("commands/reset.zig");
const Position = @import("commands/position.zig");
const Sort = @import("commands/sort.zig");

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
        /// stored as an integer, need to do / 10 to get real value
        now_cost: u8,
    };
};

const Menu = enum {
    search_table,
    selected,
    cmd,
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

    var all_players = std.ArrayList(Player).init(allocator);
    defer all_players.deinit();

    for (resp.value.elements) |element| {
        const team_name = team_map.get(element.team_code) orelse std.debug.panic("Team code {d} not found in team map!", .{element.team_code});
        const bg = Teams.fromString(team_name).color();
        const player = Player{
            .name = element.web_name,
            .position = Player.Position.fromElementType(element.element_type),
            .position_name = Player.fromElementType(element.element_type),
            .price = @as(f32, @floatFromInt(element.now_cost)) / 10,
            .team_name = team_name,
            .team_id = element.team_code,
            .background_color = bg,
            .foreground_color = Colors.getTextColor(bg),
        };
        try player_map.put(allocator, element.web_name, player);
        // by default add all players to the initial filter
        try all_players.append(player);
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

    var cmd_input = TextInput.init(allocator, &vx.unicode);
    defer cmd_input.deinit();

    try vx.queryTerminal(tty.anyWriter(), 1 * std.time.ns_per_s);

    var filtered_players = try all_players.clone();
    defer filtered_players.deinit();

    var event_arena = std.heap.ArenaAllocator.init(allocator);
    defer event_arena.deinit();

    var filtered = try Table.init(allocator, "Select a player");
    defer filtered.deinit(allocator);
    filtered.makeActive();

    var selected = try Table.init(allocator, "Selected players");
    defer selected.deinit(allocator);

    var lineup: Lineup = .init();

    var active_menu: Menu = .search_table;

    while (true) {
        defer _ = event_arena.reset(.retain_capacity);
        defer tty_buf_writer.flush() catch {};

        const event_alloc = event_arena.allocator();
        const event = loop.nextEvent();

        switch (event) {
            .key_press => |key| {
                if (key.matches('c', .{ .ctrl = true })) {
                    break;
                }
                row_navigation: {
                    var table: *Table = switch (active_menu) {
                        .search_table => &filtered,
                        .selected => &selected,
                        else => break :row_navigation,
                    };

                    if (key.matches(Key.up, .{})) {
                        table.moveUp();
                    } else if (key.matches(Key.down, .{})) {
                        table.moveDown();
                    }
                }

                // enter cmd mode
                if (active_menu != .cmd and key.matchesAny(&.{ ':', ';', '/' }, .{})) {
                    active_menu = .cmd;
                }

                switch (active_menu) {
                    .cmd => cmd: {
                        if (key.matchExact(vaxis.Key.enter, .{})) {
                            //default to making the active menu, after enter is clicked, the search table
                            active_menu = .search_table;
                            const message = try cmd_input.toOwnedSlice();
                            defer allocator.free(message);

                            if (message.len == 0) break :cmd;

                            const arg = message[1..];
                            if (std.mem.eql(u8, "q", arg) or
                                std.mem.eql(u8, "quit", arg) or
                                std.mem.eql(u8, "exit", arg)) return;

                            var it = std.mem.tokenizeSequence(u8, arg, " ");
                            if (it.next()) |command| {
                                // TODO: error handling
                                const go = Go.handle(command, .{
                                    .it = &it,
                                    .players_table = &filtered,
                                }) catch break :cmd;
                                if (go) break :cmd;

                                // TODO: error handling
                                const search = Search.handle(command, .{
                                    .allocator = event_alloc,
                                    .it = it,
                                    .player_map = player_map,
                                    .player_table = &filtered,
                                    .filtered_players = &filtered_players,
                                }) catch break :cmd;

                                if (search) break :cmd;

                                // TODO: error handling
                                const sort = Sort.handle(command, .{
                                    .it = &it,
                                    .filtered_players = &filtered_players,
                                }) catch break :cmd;

                                if (sort) break :cmd;

                                // TODO: error handling
                                const filter = Position.handle(command, .{
                                    .it = it,
                                    .player_table = &filtered,
                                    .filtered_players = &filtered_players,
                                    .all_players = all_players,
                                }) catch break :cmd;

                                if (filter) break :cmd;

                                const reset = Reset.handle(command, .{
                                    .filtered_players = &filtered_players,
                                    .all_players = &all_players,
                                }) catch break :cmd;

                                if (reset) break :cmd;
                            }
                        } else {
                            // add the text into the buffer
                            try cmd_input.update(.{ .key_press = key });
                        }
                    },
                    .search_table => {
                        if (key.matchExact(Key.enter, .{})) {
                            lineup.appendAny(filtered_players.items[filtered.context.row]) catch {
                                //TODO: signify selection full somehow?
                            };
                        } else if (key.matches(Key.right, .{})) {
                            active_menu = .selected;
                            selected.makeActive();
                            filtered.makeNormal();
                        } else if (key.matchExact(Key.enter, .{})) {
                            lineup.appendAny(filtered_players.items[filtered.context.row]) catch {
                                //TODO: signify selection full somehow?
                            };
                        }
                    },
                    .selected => selected: {
                        if (key.matches(Key.left, .{})) {
                            active_menu = .search_table;
                            filtered.makeActive();
                            selected.makeNormal();
                        } else if (key.matchExact(Key.enter, .{})) {
                            lineup.remove(selected.context.row);
                        } else if (key.matchExact(Key.space, .{})) {
                            const rows = selected.context.sel_rows orelse {
                                selected.context.sel_rows = try allocator.alloc(u16, 1);
                                selected.context.sel_rows.?[0] = selected.context.row;
                                break :selected;
                            };
                            defer {
                                allocator.free(selected.context.sel_rows.?);
                                selected.context.sel_rows = null;
                            }
                            // if we click an already selected one, unselect
                            if (selected.context.row == rows[0]) break :selected;

                            // if we are still here, swap them
                            std.mem.swap(?Player, &lineup.players[selected.context.row], &lineup.players[rows[0]]);
                        }
                    },
                }
            },

            .winsize => |ws| try vx.resize(allocator, tty.anyWriter(), ws),
            else => {},
        }

        const win = vx.window();

        win.clear();

        // left table
        const filtered_win = win.child(.{
            .x_off = 1,
            .y_off = 2,
            .width = win.width / 2,
            .height = win.height / 2,
        });

        try filtered.draw(event_alloc, win, filtered_win, filtered_players);

        // right table
        const selected_win = win.child(.{
            .x_off = filtered_win.width + filtered_win.x_off + 2,
            .y_off = filtered_win.y_off,
            .width = win.width / 2,
            .height = win.height,
        });
        var buf: [15]Player = undefined;
        lineup.toString(&buf);
        const players = std.ArrayList(Player).fromOwnedSlice(allocator, &buf);

        try selected.draw(event_alloc, win, selected_win, players);

        // bottom bar
        if (active_menu == .cmd) {
            const bottom_bar = win.child(.{
                .x_off = 0,
                .y_off = win.height - 1,
                .width = win.width,
                .height = 1,
            });
            bottom_bar.fill(.{ .style = .{ .bg = Colors.light_blue } });
            cmd_input.draw(bottom_bar);
        }

        const tty_writer = tty_buf_writer.writer().any();

        try vx.render(tty_writer);
    }
}

const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
    focus_in,
};
