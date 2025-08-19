const command_list = [_]type{
    Go,
    Refresh,
    Search,
    Reset,
    Position,
    Sort,
    Quit,
    Horizon,
};

pub fn main() !void {
    var allocator_instance = std.heap.GeneralPurposeAllocator(.{
        .stack_trace_frames = if (std.debug.sys_can_stack_trace) 10 else 0,
        .resize_stack_traces = true,
    }).init;
    defer _ = allocator_instance.deinit();

    const allocator = allocator_instance.allocator();

    // parse all player info
    var static_data = try GetStatic.call(allocator);
    defer static_data.deinit();

    var fixtures_data = try GetFixtures.call(allocator);
    defer fixtures_data.deinit();

    var player_map = std.AutoHashMapUnmanaged(u32, Player).empty;
    defer player_map.deinit(allocator);

    const TeamNames = struct { full: []const u8, short: []const u8 };
    var team_name_map = std.AutoHashMapUnmanaged(u32, TeamNames).empty;
    defer team_name_map.deinit(allocator);

    for (static_data.value.teams) |team| {
        try team_name_map.put(allocator, team.id, .{ .full = team.name, .short = team.short_name });
    }

    const next_gw: u8 = blk: {
        for (static_data.value.events, 0..) |event, i| {
            if (event.is_next == true) break :blk @intCast(i);
        }
        @panic("Cannot find next gameweek!");
    };

    var all_players = std.ArrayList(Player).init(allocator);
    defer all_players.deinit();

    // prepare team data
    var match_map = std.AutoHashMapUnmanaged(u32, std.ArrayList(Match)).empty;

    defer {
        var it = match_map.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.*.deinit();
        }
        defer match_map.deinit(allocator);
    }

    for (fixtures_data.value) |fixture| {
        var is_home = true;
        for ([_]u32{ fixture.team_h, fixture.team_a }, [_]u32{ fixture.team_a, fixture.team_h }) |team_id, opponent| {
            // invert is_home for the second cycle. goes back to true for the first
            defer is_home = !is_home;
            const gop = try match_map.getOrPut(allocator, team_id);
            const names = team_name_map.get(opponent) orelse @panic("Team name not found!");
            const temp = Match{
                .opponent_id = opponent,
                .venue = if (is_home) .home else .away,
                .opponent_name = names.full,
                .opponent_short = names.short,
            };

            if (gop.found_existing) {
                try gop.value_ptr.*.append(temp);
            } else {
                var list = std.ArrayList(Match).init(allocator);
                try list.append(temp);
                gop.key_ptr.* = team_id;
                gop.value_ptr.* = list;
            }
        }
    }

    var team_map: std.AutoHashMapUnmanaged(u32, Team) = .empty;
    defer team_map.deinit(allocator);

    var schedule_iterator = match_map.iterator();
    while (schedule_iterator.next()) |schedule| {
        const match = match_map.get(schedule.key_ptr.*) orelse @panic("Schedule key missing from match map");
        const names = team_name_map.get(schedule.key_ptr.*) orelse @panic("Schedule key missing from name map");

        const team = Team{
            .name = names.full,
            .opponents = match.items,
        };
        try team_map.put(allocator, schedule.key_ptr.*, team);
    }

    for (static_data.value.elements) |element| {
        const names = team_name_map.get(element.team) orelse std.debug.panic("Team code {d} not found in team map!", .{element.team});
        const bg = Teams.fromString(names.full).color();
        const player = Player{
            .name = element.web_name,
            .position = Player.Position.fromElementType(element.element_type),
            .position_name = Player.fromElementType(element.element_type),
            .price = @as(f32, @floatFromInt(element.now_cost)) / 10,
            .team_name = names.full,
            .team_id = element.team,
            .background_color = bg,
            .foreground_color = Colors.getTextColor(bg),
        };
        try player_map.put(allocator, element.id, player);
        // by default add all players to the initial filter
        try all_players.append(player);
    }

    // read team data from config
    var season_selections: SeasonSelection = try .init(allocator, 5);
    defer season_selections.deinit(allocator);

    season_selections.active_idx = next_gw;

    readTeam: {
        var team_list: Team.TeamList = .init();
        var selection: GameweekSelection = .init();
        // if team.json doesn't exist, leave gw_selection empty
        const team_data = Config.getTeam(allocator) catch break :readTeam;
        defer team_data.deinit();
        for (team_data.value.picks) |pick| {
            const player = player_map.get(pick.element);
            if (player) |pl| {
                try selection.appendRaw(pl);
                const team = team_map.get(pl.team_id.?) orelse @panic("Team not found in team map!");
                try team_list.appendAny(team);
            }
        }
        selection.in_the_bank = @floatFromInt(team_data.value.transfers.bank / 10);
        selection.lineup_value = @floatFromInt(team_data.value.transfers.value / 10);
        selection.free_transfers = @intCast(team_data.value.transfers.limit orelse 0);

        season_selections.insertGameweek(selection, next_gw);
        season_selections.active_idx = next_gw;

        season_selections.fixture_table[season_selections.active_idx].team_list = team_list;
    }

    var descriptions: [command_list.len]CommandDescription = undefined;
    inline for (command_list, 0..) |cmd, i| {
        descriptions[i] = cmd.description;
    }

    var command_helper: CommandHelper = .init(&descriptions);

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

    var filtered = try PlayerTable.init(allocator, "Select a player");
    defer filtered.deinit(allocator);
    filtered.table.makeActive();

    var selected = try LineupTable.init(allocator, "Selected players");
    defer selected.deinit(allocator);

    var active_menu: Menu = .search_table;
    // Used for smooth transitioning in and out of the gameweek selector menu
    var previous_menu: Menu = active_menu;

    var error_message: ErrorMessage = try .init(allocator, &previous_menu, &active_menu);
    defer error_message.deinit(allocator);

    var gw_selection: GameweekSelection = season_selections.gameweek_selections[season_selections.active_idx];
    var fixture_table: FixtureTable = season_selections.fixture_table[season_selections.active_idx];

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
                // if in error message state, wait for button press to clear message
                if (active_menu == .error_message) {
                    error_message.clearMessage();
                }
                if (key.matchExact(Key.tab, .{})) {
                    switch (active_menu) {
                        .gameweek_selector => {
                            active_menu = previous_menu;
                        },
                        else => {
                            previous_menu = active_menu;
                            active_menu = .gameweek_selector;
                        },
                    }
                }
                row_navigation: {
                    var active_table: *TableCommon = switch (active_menu) {
                        .search_table => &filtered.table,
                        .selected => &selected.table,
                        else => break :row_navigation,
                    };

                    if (key.matches(Key.up, .{})) {
                        active_table.moveUp();
                    } else if (key.matches(Key.down, .{})) {
                        active_table.moveDown();
                    }
                }

                // enter cmd mode
                if (active_menu != .cmd and key.matchesAny(&.{ ':', ';', '/' }, .{})) {
                    active_menu = .cmd;
                }

                switch (active_menu) {
                    .error_message => {},
                    .gameweek_selector => {
                        if (key.matchExact(Key.left, .{})) {
                            season_selections.decrementIndex(1);

                            gw_selection = season_selections.getActiveGameweek();
                            fixture_table = season_selections.getActiveFixture();
                        } else if (key.matches(Key.right, .{})) {
                            season_selections.incrementIndex(1);

                            gw_selection = season_selections.getActiveGameweek();
                            fixture_table = season_selections.getActiveFixture();
                        }
                    },
                    .cmd => cmd: {
                        if (key.matchExact(vaxis.Key.enter, .{})) {
                            //default to making the active menu, after enter is clicked, the search table
                            active_menu = .search_table;
                            const message = try cmd_input.toOwnedSlice();
                            defer allocator.free(message);

                            if (message.len == 0) break :cmd;

                            const arg = message[1..];

                            var it = std.mem.tokenizeSequence(u8, arg, " ");
                            if (it.next()) |command| {
                                inline for (command_list) |Cmd| {
                                    switch (Cmd) {
                                        Go => {
                                            Go.handle(command, .{
                                                .it = &it,
                                                .players_table = &filtered,
                                            }) catch |err| switch (err) {
                                                Go.Errors.EmptyToken => {},
                                                Go.Errors.TokenNaN => {
                                                    try error_message.setErrorMessage("Line number is not a number!", .cmd);
                                                },
                                            };
                                        },
                                        Refresh => {
                                            Refresh.handle(command, .{
                                                .allocator = allocator,
                                                .static_data = &static_data,
                                                .fixtures_data = &fixtures_data,
                                            }) catch |err| switch (err) {
                                                Refresh.Errors.FailedToRefetch => {
                                                    try error_message.setErrorMessage("Failed to fetch data!", .cmd);
                                                },
                                            };
                                        },
                                        Search => {
                                            Search.handle(command, .{
                                                .allocator = event_alloc,
                                                .it = it,
                                                .player_map = player_map,
                                                .player_table = &filtered,
                                                .filtered_players = &filtered_players,
                                            }) catch |err| switch (err) {
                                                Search.Errors.EmptyString => {
                                                    try error_message.setErrorMessage("You must enter a string!", .cmd);
                                                },
                                                Search.Errors.OOM => return err,
                                            };
                                        },
                                        Sort => {
                                            Sort.handle(command, .{
                                                .it = &it,
                                                .filtered_players = &filtered_players,
                                            }) catch |err| switch (err) {
                                                Sort.Errors.EmptyString => {},
                                                Sort.Errors.UnknownSortType => {
                                                    try error_message.setErrorMessage("You must enter a valid sort type!", .cmd);
                                                },
                                                Sort.Errors.OOM => return err,
                                            };
                                        },
                                        Position => {
                                            Position.handle(command, .{
                                                .it = it,
                                                .player_table = &filtered,
                                                .filtered_players = &filtered_players,
                                                .all_players = all_players,
                                            }) catch |err| switch (err) {
                                                Position.Errors.EmptyString => {},
                                                Position.Errors.InvalidPosition => {
                                                    try error_message.setErrorMessage("You must enter a valid position!", .cmd);
                                                },
                                                Position.Errors.OOM => return err,
                                            };
                                        },
                                        Reset => {
                                            Reset.handle(command, .{
                                                .filtered_players = &filtered_players,
                                                .all_players = &all_players,
                                            }) catch |err| switch (err) {
                                                Reset.Errors.OOM => return err,
                                            };
                                        },
                                        Quit => {
                                            const quit = Quit.shouldCall(arg);
                                            if (quit) return;
                                        },
                                        Horizon => {
                                            Horizon.handle(command, .{
                                                .allocator = allocator,
                                                .fixture_table = &fixture_table,
                                                .it = &it,
                                            }) catch |err| switch (err) {
                                                Horizon.Errors.EmptyEndToken, Horizon.Errors.EmptyStartToken => {},
                                                Horizon.Errors.StartTokenNaN, Horizon.Errors.EndTokenNaN => {
                                                    try error_message.setErrorMessage("You must enter a number!", .cmd);
                                                },
                                            };
                                        },
                                        else => @compileError(std.fmt.comptimePrint("No implementation for command {}.", .{Cmd})),
                                    }
                                }
                            }
                        } else {
                            // add the text into the buffer
                            try cmd_input.update(.{ .key_press = key });
                        }
                    },
                    .search_table => search_table: {
                        const currently_selected_player = filtered_players.items[filtered.table.context.row];
                        if (key.matchExact(Key.enter, .{})) {
                            gw_selection.append(currently_selected_player) catch |err| {
                                switch (err) {
                                    GameweekSelection.AppendErrors.MissingFunds => try error_message.setErrorMessage("Insufficient funds!", .search_table),
                                    GameweekSelection.AppendErrors.SelectionFull => try error_message.setErrorMessage("GameweekSelection is full!", .search_table),
                                }
                                break :search_table;
                            };
                            const team = team_map.get(currently_selected_player.team_id.?) orelse @panic("Team not found in team map!");
                            try fixture_table.team_list.appendAny(team);
                        } else if (key.matches(Key.right, .{})) {
                            active_menu = .selected;
                            selected.table.makeActive();
                            filtered.table.makeNormal();
                        }
                    },
                    .selected => selected: {
                        if (key.matches(Key.left, .{})) {
                            active_menu = .search_table;
                            filtered.table.makeActive();
                            selected.table.makeNormal();
                        } else if (key.matchExact(Key.enter, .{})) {
                            gw_selection.remove(selected.table.context.row);
                            fixture_table.team_list.remove(selected.table.context.row);
                        } else if (key.matchExact(Key.space, .{})) {
                            const rows = selected.table.context.sel_rows orelse {
                                selected.table.context.sel_rows = try allocator.alloc(u16, 1);
                                selected.table.context.sel_rows.?[0] = selected.table.context.row;
                                break :selected;
                            };
                            defer {
                                allocator.free(selected.table.context.sel_rows.?);
                                selected.table.context.sel_rows = null;
                            }
                            // if we click an already selected one, unselect
                            if (selected.table.context.row == rows[0]) break :selected;

                            // if we are still here, swap them
                            std.mem.swap(?Player, &gw_selection.players[selected.table.context.row], &gw_selection.players[rows[0]]);
                            std.mem.swap(
                                ?Team,
                                &fixture_table.team_list.teams[selected.table.context.row],
                                &fixture_table.team_list.teams[rows[0]],
                            );
                        }
                    },
                }
            },

            .winsize => |ws| try vx.resize(allocator, tty.anyWriter(), ws),
            else => {},
        }

        const win = vx.window();

        win.clear();

        const ROWS_PER_TABLE = 15;
        // running total of current offsets
        var x_off: i17 = 1;
        const y_off: i17 = 2;
        // left table
        const filtered_win = win.child(.{
            .x_off = x_off,
            .y_off = y_off,
            .width = win.width / 3,
            .height = ROWS_PER_TABLE + 2,
        });

        try filtered.draw(
            event_alloc,
            win,
            filtered_win,
            filtered_players,
        );

        // gw_selection table
        x_off += filtered_win.width + 2;
        const selected_win = win.child(.{
            .x_off = x_off,
            .y_off = y_off,
            .width = win.width / 3,
            .height = ROWS_PER_TABLE + 2,
        });

        var stats_buf: [1024]u8 = undefined;
        var transfer_buf: [1024]u8 = undefined;

        try selected.draw(
            event_alloc,
            win,
            selected_win,
            gw_selection,
            .{
                .stats_buf = &stats_buf,
                .transfer_buf = &transfer_buf,
            },
        );

        // team table
        x_off += selected_win.width;
        const team_win = win.child(.{
            .x_off = x_off,
            .y_off = y_off,
            .width = win.width / 3,
            .height = ROWS_PER_TABLE + 2,
        });
        var team_buf: [15]Team = undefined;

        season_selections.fixture_table[season_selections.active_idx].team_list.toString(&team_buf);
        const fixtures = std.ArrayList(Team).fromOwnedSlice(allocator, &team_buf);

        try fixture_table.draw(
            event_alloc,
            team_win,
            fixtures,
        );

        // bottom bar
        if (active_menu == .cmd) {
            const bottom_bar = win.child(.{
                .x_off = 0,
                .y_off = win.height - 1,
                .width = win.width,
                .height = 1,
            });
            bottom_bar.fill(.{ .style = .{ .bg = Colors.light_blue } });
            cmd_input.drawWithStyle(bottom_bar, .{ .bg = Colors.light_blue });

            const message = cmd_input.buf.firstHalf();
            try command_helper.draw(win, message);
        }
        // error messages
        const err_msg_segment = vaxis.Cell.Segment{
            .text = error_message.getMessage(),
            .style = .{ .bold = true },
        };
        const err_msg_bar = win.child(.{
            .x_off = 0,
            .y_off = win.height - 2,
            .width = win.width,
            .height = 1,
        });
        _ = err_msg_bar.printSegment(err_msg_segment, .{});

        const tty_writer = tty_buf_writer.writer().any();

        try vx.render(tty_writer);
    }
}

const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
    focus_in,
};

pub fn panic(
    msg: []const u8,
    error_return_trace: ?*std.builtin.StackTrace,
    ret_addr: ?usize,
) noreturn {
    vaxis.recover();
    std.log.err("{s}\n\n", .{msg});
    if (error_return_trace) |t| std.debug.dumpStackTrace(t.*);
    std.debug.dumpCurrentStackTrace(ret_addr orelse @returnAddress());

    std.process.exit(1);
}

const ErrorMessage = @import("components/error_message.zig");

const Player = @import("types.zig").Player;

const Config = @import("config.zig");

const vaxis = @import("vaxis");
const TextInput = vaxis.widgets.TextInput;
const Key = vaxis.Key;
const TableContext = vaxis.widgets.Table.TableContext;

const CommandDescription = @import("commands/command.zig");

const CommandHelper = @import("components/command_helper.zig");
const TableCommon = @import("components/table_common.zig");
const PlayerTable = @import("components/player_table.zig");
const LineupTable = @import("components/lineup_table.zig");
const FixtureTable = @import("components/fixture_table.zig");

const SeasonSelection = @import("season_selection.zig");

const GameweekSelection = @import("gameweek_selection.zig");

const Menu = @import("components/menus.zig").Menu;

const Team = @import("team.zig");
const Match = Team.Match;

const Colors = @import("colors.zig");
const Teams = @import("fpl.zig").Teams;
const GetStatic = @import("fpl.zig").GetStatic;
const GetFixtures = @import("fpl.zig").GetFixtures;

const Go = @import("commands/go.zig");
const Refresh = @import("commands/refresh.zig");
const Search = @import("commands/search.zig");
const Reset = @import("commands/reset.zig");
const Position = @import("commands/position.zig");
const Sort = @import("commands/sort.zig");
const Quit = @import("commands/quit.zig");
const Horizon = @import("commands/horizon.zig");

const std = @import("std");

test "tests:beforeAll" {
    std.testing.refAllDecls(@This());
}

test "tests:afterAll" {
    const Benchmark = @import("test_runner.zig").Benchmark;
    Benchmark.analyze(std.heap.smp_allocator);
}
