players: [15]?Player,
lineup_value: f32,
in_the_bank: f32,
transfers_made: u8,
free_transfers: u8,
hit_value: u8,

const Self = @This();

pub fn init() Self {
    return Self{
        .players = [_]?Player{null} ** 15,
        .lineup_value = 0,
        .in_the_bank = 0,
        .transfers_made = 0,
        .free_transfers = 0,
        .hit_value = 0,
    };
}

pub fn toString(self: Self, buf: *[15]Player) void {
    for (self.players, 0..) |player, i| {
        if (player) |pl| {
            buf[i] = pl;
        } else buf[i] = Player.empty;
    }
}

pub fn isValid(self: Self) bool {
    const MAX_PER_TEAM = 3;
    var gk_count: u4 = 0;
    var def_count: u4 = 0;
    var mid_count: u4 = 0;
    var fwd_count: u4 = 0;

    const Team = struct { id: u32, count: u4 = 1 };
    var teams: [20]Team = undefined;
    var team_count: u8 = 0;
    player_loop: for (self.players) |player| {
        if (player) |pl| {
            // do not use this on empty players, pretty please.
            switch (pl.position.?) {
                .gk => gk_count += 1,
                .def => def_count += 1,
                .mid => mid_count += 1,
                .fwd => fwd_count += 1,
            }
            for (0..team_count) |i| {
                if (teams[i].id == pl.team_id) {
                    teams[i].count += 1;
                    // early exit if player count exceeds maximum, continue loop if not
                    // continuing the loop manually is done to deal with the teams list
                    if (teams[i].count > MAX_PER_TEAM) return false else continue :player_loop;
                }
            }
            // if we are here that means a team was not found inside []teams
            teams[team_count] = Team{ .id = pl.team_id.? };
            team_count += 1;
        }
    }

    // no more than 2 goalkeepers
    if (gk_count > 2) return false;

    // no more than 5 defenders
    if (def_count > 5) return false;

    // no more than 5 midfielders
    if (mid_count > 5) return false;

    // no more than 3 forwards
    if (fwd_count > 3) return false;

    //if all is good...
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

pub fn remove(self: *Self, index: u16) void {
    if (self.players[index]) |pl| {
        self.lineup_value -= pl.price.?;
        self.in_the_bank += pl.price.?;
        self.players[index] = null;
    }
}

const Player = @import("types.zig").Player;
