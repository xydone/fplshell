phrases: [][]const u8,
description: ?[]const u8,
params: ?[]Params,
pub const Params = struct {
    name: []const u8,
    description: ?[]const u8,
    /// NOTE : A parameter which appears N or unlimited amount of times, but is not the last parameter in the list is not supported.
    count: union(enum) {
        /// repeats up to N times
        limited: u8,
        unlimited: void,
    } = .{
        // the default is a parameter which appears once
        .limited = 1,
    },
};

const Self = @This();
const std = @import("std");
