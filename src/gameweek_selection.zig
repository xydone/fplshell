players: [15]?Player, //TODO: turn this field into a hashmap. requires a vaxis table rewrite
is_valid_formation: bool,
lineup_value: f32,
in_the_bank: f32,
transfers_made: u8,
free_transfers: u8,
amount_of_hits: u8,
chip_active: ?Chips,

const Self = @This();

pub fn init() Self {
    return Self{
        .players = [_]?Player{null} ** 15,
        .lineup_value = 0,
        .in_the_bank = 0,
        .transfers_made = 0,
        .free_transfers = 0,
        .amount_of_hits = 0,
        .is_valid_formation = false,
        .chip_active = null,
    };
}

pub fn toString(self: Self, buf: *[15]Player) void {
    for (self.players, 0..) |player, i| {
        if (player) |pl| {
            buf[i] = pl;
        } else buf[i] = Player.empty;
    }
}

pub fn isValidFormation(self: Self) bool {
    var starters: struct {
        gk: u4 = 0,
        def: u4 = 0,
        mid: u4 = 0,
        fwd: u4 = 0,
    } = .{};

    for (self.players[0..11]) |maybe_player| {
        const player = maybe_player orelse continue;
        // do not use this on empty players, pretty please.
        switch (player.position.?) {
            .gk => starters.gk += 1,
            .def => starters.def += 1,
            .mid => starters.mid += 1,
            .fwd => starters.fwd += 1,
        }
    }

    if (starters.gk != 1) return false;
    if (starters.def < 3) return false;
    if (starters.fwd < 1) return false;
    return true;
}

pub fn isValid(self: *Self) bool {
    const MAX_PER_TEAM = 3;

    var total: struct {
        gk: u4 = 0,
        def: u4 = 0,
        mid: u4 = 0,
        fwd: u4 = 0,
    } = .{};

    const Team = struct { id: u32, count: u4 = 1 };
    var teams: [20]Team = undefined;
    var team_count: u8 = 0;

    player_loop: for (self.players) |maybe_player| {
        const player = maybe_player orelse continue;
        // do not use this on empty players, pretty please.
        switch (player.position.?) {
            .gk => total.gk += 1,
            .def => total.def += 1,
            .mid => total.mid += 1,
            .fwd => total.fwd += 1,
        }
        for (0..team_count) |i| {
            if (teams[i].id == player.team_id) {
                teams[i].count += 1;
                // early exit if player count exceeds maximum, continue loop if not
                // continuing the loop manually is done to deal with the teams list
                if (teams[i].count > MAX_PER_TEAM) return false else continue :player_loop;
            }
        }
        // if we are here that means a team was not found inside []teams
        teams[team_count] = Team{ .id = player.team_id.? };
        team_count += 1;
    }

    if (total.gk > 2) return false;
    if (total.def > 5) return false;
    if (total.mid > 5) return false;
    if (total.fwd > 3) return false;

    self.is_valid_formation = self.isValidFormation();

    return true;
}

fn canAppend(self: Self, player: Player) bool {
    var player_count: u4 = 0;
    var has_inserted = false;
    var pseudo_lineup = self;
    for (self.players, 0..) |pl, i| {
        if (pl) |_| player_count += 1 else if (!has_inserted) {
            // doing this to avoid an extra loop

            // if an empty slot is found, populate it with the future insert
            pseudo_lineup.players[i] = player;
            has_inserted = true;
        }
    }
    // if we already have a full squad, return false early
    if (player_count == 15) return false;

    // we do not have a full squad, check if its valid
    return pseudo_lineup.isValid();
}

pub const AppendErrors = error{ SelectionFull, MissingFunds };
pub fn append(self: *Self, player: Player) AppendErrors!void {
    // check if we can append a player before appending
    // if not possible exit early
    if (!self.canAppend(player)) return error.SelectionFull;
    inline for (0..15) |i| {
        if (self.players[i] == null) {
            if (self.in_the_bank - player.price.? < 0) return error.MissingFunds;
            self.players[i] = player;
            self.lineup_value += player.price.?;
            self.in_the_bank -= player.price.?;

            return;
        }
    }
    return error.SelectionFull;
}

/// Appends will not affect team and itb value
pub fn appendRaw(self: *Self, player: Player) error{SelectionFull}!void {
    inline for (0..15) |i| {
        if (self.players[i] == null) {
            self.players[i] = player;
            return;
        }
    }
    return error.SelectionFull;
}

pub fn remove(self: *Self, id: u32) void {
    for (self.players, 0..) |maybe_player, i| {
        const player = maybe_player orelse continue;
        if (player.id != id) continue;
        self.players[i] = null;
        self.lineup_value -= player.price.?;
        self.in_the_bank += player.price.?;
    }
}

pub fn addFreeTransfers(self: *Self, amount: u8) void {
    const free_transfers: u8 = self.free_transfers + amount;
    self.free_transfers = if (free_transfers > MAX_FREE_TRANSFERS) MAX_FREE_TRANSFERS else free_transfers;
}
pub fn removeFreeTransfers(self: *Self, amount: u8) void {
    self.free_transfers = std.math.sub(u8, self.free_transfers, amount) catch 0;
}

pub fn takeHit(self: *Self, amount: u8) void {
    self.amount_of_hits += amount;
}

pub fn activateChip(self: *Self, chip: Chips) void {
    self.chip_active = chip;
    switch (chip) {
        .wildcard, .wc => {
            // clear hits
            self.amount_of_hits = 0;
            // give unlimited transfers for this gameweek
            self.free_transfers = 15;
        },
        .free_hit, .fh => {
            // clear hits
            self.amount_of_hits = 0;
            // give unlimited transfers for this gameweek
            self.free_transfers = 15;
        },
        .bench_boost, .bb => {},
        .triple_captain, .tc => {},
    }
}

const MAX_FREE_TRANSFERS = @import("types.zig").MAX_FREE_TRANSFERS;
const Chips = @import("types.zig").Chips;

const Player = @import("types.zig").Player;
const std = @import("std");
