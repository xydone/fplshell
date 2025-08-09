phrases: [][]const u8,
description: ?[]const u8,
params: ?[]Params,
pub const Params = struct { name: []const u8, description: ?[]const u8 };

const Self = @This();
const std = @import("std");
