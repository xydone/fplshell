const command_list = [_]type{
    Go,
    Search,
    Reset,
    Filter,
    Quit,
    Horizon,
    Save,
    Load,
    Chip,
};

var debug_allocator: std.heap.DebugAllocator(.{}) = .init;

pub fn main() !void {
    const allocator, const is_debug = gpa: {
        if (builtin.target.os.tag == .wasi) break :gpa .{ std.heap.wasm_allocator, false };
        break :gpa switch (builtin.mode) {
            .Debug, .ReleaseSafe => .{ debug_allocator.allocator(), true },
            .ReleaseFast, .ReleaseSmall => .{ std.heap.smp_allocator, false },
        };
    };
    defer if (is_debug) {
        _ = debug_allocator.deinit();
    };
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

    const visual_settings_file = Config.VisualSettingsFile.get(allocator) catch return error.NoColorFile;
    defer visual_settings_file.deinit(allocator);

    const visual_settings = visual_settings_file.toVisualSettings();

    for (static_data.value.elements) |element| {
        const names = team_name_map.get(element.team) orelse std.debug.panic("Team code {d} not found in team map!", .{element.team});
        const bg = Teams.fromString(names.full).color(visual_settings.team_colors);
        const player = Player{
            .id = element.id,
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
    var season_selections: SeasonSelection = try .init(
        allocator,
        visual_settings,
        5,
    );
    defer season_selections.deinit(allocator);

    season_selections.active_idx = next_gw;

    const config = Config.get(allocator) catch return error.CannotReadConfigFile;
    defer config.deinit(allocator);

    switch (config.team_source) {
        .file => |file| file: {
            var selection: GameweekSelection = .init();
            // if team.json doesn't exist, leave gw_selection empty
            const team_data = Config.TeamFile.get(allocator, file) catch break :file;
            defer team_data.deinit();

            for (team_data.value.picks) |pick| {
                const player = player_map.get(pick.element);
                if (player) |pl| {
                    try selection.appendRaw(pl);
                }
            }
            selection.in_the_bank = @floatFromInt(team_data.value.transfers.bank / 10);
            selection.lineup_value = @floatFromInt(team_data.value.transfers.value / 10);
            selection.is_valid_formation = selection.isValidFormation();

            selection.addFreeTransfers(@intCast(team_data.value.transfers.limit orelse 0));

            for (next_gw..GAMEWEEK_COUNT) |i| {
                selection.addFreeTransfers(1);
                season_selections.insertGameweek(selection, @intCast(i));
            }
        },
        .id => |id| {
            var last_selection: ?GameweekSelection = null;

            var response_idx: u8 = 0;
            while (response_idx < next_gw) : (response_idx += 1) {
                var selection: GameweekSelection = .init();
                const entry_history = try GetEntryHistory.call(allocator, id, response_idx + 1);
                defer entry_history.deinit();

                for (entry_history.value.picks) |pick| {
                    const player = player_map.get(pick.element);
                    if (player) |pl| {
                        try selection.appendRaw(pl);
                    }
                }

                selection.in_the_bank = @floatFromInt(entry_history.value.entry_history.bank / 10);
                selection.lineup_value = @floatFromInt(entry_history.value.entry_history.value / 10);

                var transfers: u8 = 0;
                // add one transfer
                if (last_selection) |ls| transfers = ls.free_transfers + 1;
                // remove transfers used this gameweek
                transfers -= @intCast(entry_history.value.entry_history.event_transfers);

                selection.addFreeTransfers(transfers);

                selection.is_valid_formation = selection.isValidFormation();

                season_selections.insertGameweek(selection, response_idx);
                last_selection = selection;
            }

            var propagate_idx: u8 = response_idx;
            while (propagate_idx < GAMEWEEK_COUNT) : (propagate_idx += 1) {
                // add free transfers
                last_selection.?.addFreeTransfers(1);
                season_selections.insertGameweek(last_selection.?, propagate_idx);
            }
        },
    }

    var descriptions: [command_list.len]CommandDescription = undefined;
    inline for (command_list, 0..) |cmd, i| {
        descriptions[i] = cmd.description;
    }

    var command_helper: CommandHelper = .init(&descriptions, visual_settings);

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

    var search_table: PlayerTable = try .init(
        allocator,
        visual_settings,
        "Select a player",
    );
    defer search_table.deinit(allocator);
    search_table.table.makeActive();

    var selected = try LineupTable.init(allocator, visual_settings, "Selected players");
    defer selected.deinit(allocator);

    var active_menu: Menu = .search_table;
    // Used for smooth transitioning in and out of the gameweek selector menu
    var previous_menu: Menu = active_menu;

    var error_message: ErrorMessage = try .init(allocator, &previous_menu, &active_menu);
    defer error_message.deinit(allocator);

    var gw_selection: GameweekSelection = season_selections.gameweek_selections[season_selections.active_idx];
    var fixture_table: FixtureTable = season_selections.fixture_table[season_selections.active_idx];

    var loaded_transfer_plan: ?Load.LoadResponse = null;
    defer if (loaded_transfer_plan) |lt| lt.deinit();

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
                        .search_table => &search_table.table,
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
                                                .players_table = &search_table,
                                            }) catch |err| switch (err) {
                                                Go.Errors.EmptyToken => {},
                                                Go.Errors.TokenNaN => {
                                                    try error_message.setErrorMessage("Line number is not a number!", .cmd);
                                                },
                                            };
                                        },

                                        Search => {
                                            Search.handle(command, .{
                                                .allocator = event_alloc,
                                                .it = it,
                                                .player_map = player_map,
                                                .player_table = &search_table,
                                                .filtered_players = &filtered_players,
                                            }) catch |err| switch (err) {
                                                Search.Errors.EmptyString => {
                                                    try error_message.setErrorMessage("You must enter a string!", .cmd);
                                                },
                                                Search.Errors.OOM => return err,
                                            };
                                        },

                                        Filter => {
                                            Filter.handle(command, .{
                                                .it = it,
                                                .player_table = &search_table,
                                                .filtered_players = &filtered_players,
                                                .all_players = all_players,
                                            }) catch |err| switch (err) {
                                                Filter.Errors.MissingValue => {
                                                    try error_message.setErrorMessage("You entered a filter without a value!", .cmd);
                                                },
                                                Filter.Errors.InvalidFilter => {
                                                    try error_message.setErrorMessage("You must enter a valid filter!", .cmd);
                                                },
                                                Filter.Errors.InvalidPosition => {
                                                    try error_message.setErrorMessage("You must enter a valid position!", .cmd);
                                                },
                                                // TODO: handle them individually, maybe
                                                Filter.Errors.StartPriceInvalid, Filter.Errors.EndPriceInvalid, Filter.Errors.RangeMissing => {
                                                    try error_message.setErrorMessage("You must enter a valid price range!", .cmd);
                                                },
                                                Filter.Errors.PriceInvalid => {
                                                    try error_message.setErrorMessage("You must enter a valid price!", .cmd);
                                                },
                                                Filter.Errors.OOM => return err,
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
                                        Save => {
                                            Save.handle(command, .{
                                                .it = &it,
                                                .allocator = allocator,
                                                .season_selection = season_selections,
                                            }) catch try error_message.setErrorMessage("Cannot save transfer plan!", .cmd);
                                        },
                                        Load => load_blk: {
                                            const transfer_plan = Load.handle(command, .{
                                                .it = &it,
                                                .allocator = allocator,
                                                .season_selection = &season_selections,
                                            }) catch |err| switch (err) {
                                                Load.Errors.EmptyName => {
                                                    try error_message.setErrorMessage("Empty transfer plan name!", .cmd);
                                                    break :load_blk;
                                                },
                                                Load.Errors.CannotReadFile => {
                                                    try error_message.setErrorMessage("Cannot read transfer plan file!", .cmd);
                                                    break :load_blk;
                                                },
                                                Load.Errors.CannotParseFile => {
                                                    try error_message.setErrorMessage("Cannot parse transfer plan file!", .cmd);
                                                    break :load_blk;
                                                },
                                                Load.Errors.OOM => {
                                                    return err;
                                                },
                                            } orelse break :load_blk;
                                            if (loaded_transfer_plan) |lt| lt.deinit();
                                            loaded_transfer_plan = transfer_plan;

                                            // update the view for rendering
                                            gw_selection = season_selections.getActiveGameweek();
                                        },
                                        Chip => {
                                            Chip.handle(command, .{
                                                .allocator = allocator,
                                                .season_selections = &season_selections,
                                                .it = &it,
                                            }) catch |err| switch (err) {
                                                Chip.Errors.InvalidChip => {
                                                    try error_message.setErrorMessage("Chip does not exist!", .cmd);
                                                },
                                            };

                                            // update the view for rendering
                                            gw_selection = season_selections.getActiveGameweek();
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
                        if (key.matches(Key.right, .{})) {
                            active_menu = .selected;
                            selected.table.makeActive();
                            search_table.table.makeNormal();
                        }
                        // if the list is empty, the selected row will still be considered to be 1 or whatever it was before that, thus causing a runtime panic
                        if (filtered_players.items.len == 0 or search_table.table.context.row >= filtered_players.items.len) break :search_table;
                        const currently_selected_player = filtered_players.items[search_table.table.context.row];
                        if (key.matchExact(Key.enter, .{})) {
                            season_selections.appendPlayer(currently_selected_player, .{ .propagate = true }) catch |err| {
                                switch (err) {
                                    GameweekSelection.AppendErrors.MissingFunds => try error_message.setErrorMessage("Insufficient funds!", .search_table),
                                    GameweekSelection.AppendErrors.SelectionFull => try error_message.setErrorMessage("GameweekSelection is full!", .search_table),
                                }
                                break :search_table;
                            };
                            // update the view for rendering
                            gw_selection = season_selections.getActiveGameweek();
                        }
                    },
                    .selected => selected: {
                        if (key.matches(Key.left, .{})) {
                            active_menu = .search_table;
                            search_table.table.makeActive();
                            selected.table.makeNormal();
                        } else if (key.matchExact(Key.enter, .{})) {
                            season_selections.removePlayer(selected.table.context.row);

                            // update display
                            gw_selection = season_selections.getActiveGameweek();
                        } else if (key.matchExact('c', .{})) {
                            season_selections.gameweek_selections[season_selections.active_idx].captain_idx = @intCast(selected.table.context.row);

                            gw_selection = season_selections.getActiveGameweek();
                        } else if (key.matchExact('v', .{})) {
                            season_selections.gameweek_selections[season_selections.active_idx].vice_captain_idx = @intCast(selected.table.context.row);

                            gw_selection = season_selections.getActiveGameweek();
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
                            season_selections.swapPlayers(selected.table.context.row, rows[0]);

                            // update global to new state
                            gw_selection = season_selections.getActiveGameweek();
                        }
                    },
                }
            },

            .winsize => |ws| try vx.resize(allocator, tty.anyWriter(), ws),
            else => {},
        }

        const win = vx.window();

        win.clear();

        // apply a background if provided
        if (visual_settings_file.terminal_colors.background) |_| {
            win.fill(.{ .style = .{
                .bg = visual_settings.terminal_colors.background,
            } });
        }

        const ROWS_PER_TABLE = 15;
        // running total of current offsets
        var x_off: i17 = 1;
        const y_off: i17 = 2;
        // left table
        var search_table_border_menus = [_]Menu{.search_table};
        const search_table_win = createChild(.{
            .initial_layout = .{
                .x_off = x_off,
                .y_off = y_off,
                .width = win.width / 3,
                .height = ROWS_PER_TABLE + 2,
            },
            .window = win,
            .active_menu = active_menu,
            .border_menus = &search_table_border_menus,
        }, .{
            .terminal_background_color = visual_settings.terminal_colors.background,
        });

        try search_table.draw(
            event_alloc,
            win,
            search_table_win,
            filtered_players,
        );

        // selected players table
        x_off += search_table_win.width + 2;
        var selected_table_border_menus = [_]Menu{.selected};
        const selected_win = createChild(.{
            .initial_layout = .{
                .x_off = x_off,
                .y_off = y_off,
                .width = win.width / 3,
                .height = ROWS_PER_TABLE + 2,
            },
            .window = win,
            .active_menu = active_menu,
            .border_menus = &selected_table_border_menus,
        }, .{
            // everywhere except on the right
            .locations = .{ .left = true, .top = true, .bottom = true },
            .terminal_background_color = visual_settings.terminal_colors.background,
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
        var team_table_border_menus = [_]Menu{ .selected, .gameweek_selector };
        const team_win = createChild(.{
            .initial_layout = .{
                .x_off = x_off,
                .y_off = y_off,
                .width = win.width / 3,
                .height = ROWS_PER_TABLE + 2,
            },
            .window = win,
            .active_menu = active_menu,
            .border_menus = &team_table_border_menus,
        }, .{
            // if the active menu is the selected table, draw the remainder of the border on here, else default.
            .locations = if (active_menu == .selected) .{ .right = true, .top = true, .bottom = true } else CreateChildOptions.all_selected,
            .terminal_background_color = visual_settings.terminal_colors.background,
        });
        var team_buf: [15]Team = undefined;

        var team_list = Team.TeamList.init();

        for (gw_selection.players, 0..) |maybe_pl, i| {
            const player = maybe_pl orelse continue;
            const team = team_map.get(player.team_id.?) orelse @panic("Team not found in team map!");
            team_list.teams[i] = team;
        }
        team_list.toString(&team_buf);

        const fixtures = std.ArrayList(Team).fromOwnedSlice(allocator, &team_buf);

        try fixture_table.draw(
            event_alloc,
            team_win,
            fixtures,
            gw_selection.chip_active,
        );

        // bottom bar
        if (active_menu == .cmd) {
            const bottom_bar = win.child(.{
                .x_off = 0,
                .y_off = win.height - 1,
                .width = win.width,
                .height = 1,
            });
            bottom_bar.fill(.{ .style = .{ .bg = visual_settings.cmd_colors.commands_background } });
            cmd_input.drawWithStyle(bottom_bar, .{ .bg = visual_settings.cmd_colors.commands_background });

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

const GAMEWEEK_COUNT = @import("types.zig").GAMEWEEK_COUNT;
const Player = @import("types.zig").Player;

const Config = @import("config.zig");

const vaxis = @import("vaxis");
const TextInput = vaxis.widgets.TextInput;
const Color = vaxis.Color;
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

const CreateChildOptions = @import("util/window.zig").Options;
const createChild = @import("util/window.zig").createChild;

const Menu = @import("components/menus.zig").Menu;

const Team = @import("team.zig");
const Match = Team.Match;

const Colors = @import("colors.zig");
const Teams = @import("fpl.zig").Teams;
const GetStatic = @import("fpl.zig").GetStatic;
const GetFixtures = @import("fpl.zig").GetFixtures;
const GetEntryHistory = @import("fpl.zig").GetEntryHistory;

const Go = @import("commands/go.zig");
const Search = @import("commands/search.zig");
const Reset = @import("commands/reset.zig");
const Filter = @import("commands/filter.zig");
const Quit = @import("commands/quit.zig");
const Horizon = @import("commands/horizon.zig");
const Save = @import("commands/save.zig");
const Load = @import("commands/load.zig");
const Chip = @import("commands/chip.zig");

const builtin = @import("builtin");
const std = @import("std");

test "tests:beforeAll" {
    std.testing.refAllDecls(@This());
}

test "tests:afterAll" {
    const Benchmark = @import("test_runner.zig").Benchmark;
    Benchmark.analyze(std.heap.smp_allocator);
}
