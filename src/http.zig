const std = @import("std");
const log = std.log.scoped(.http);
const tls = @import("tls");
const Allocator = std.mem.Allocator;

url: []const u8,
path: []const u8,
headers: []const u8,

const Self = @This();

/// Caller owns memory
pub fn get(self: Self, allocator: Allocator, comptime ResponseType: type, options: std.json.ParseOptions) !std.json.Parsed(ResponseType) {
    const response = try self.getUnparsed(allocator);
    defer allocator.free(response);

    return try std.json.parseFromSlice(ResponseType, allocator, response, options);
}

/// Caller owns memory
pub fn getUnparsed(self: Self, allocator: Allocator) ![]const u8 {
    const uri = try std.Uri.parse(self.url);
    const host = uri.host.?.percent_encoded;
    const port = 443;

    var tcp = try std.net.tcpConnectToHost(allocator, host, port);
    defer tcp.close();

    var root_ca = try tls.config.cert.fromSystem(allocator);
    defer root_ca.deinit(allocator);

    var conn = try tls.client(tcp, .{
        .host = host,
        .root_ca = root_ca,
    });

    const req = try std.fmt.allocPrint(allocator, "GET {s} HTTP/1.0\r\nHost: {s}\r\n\r\n", .{ self.path, host });
    defer allocator.free(req);
    try conn.writeAll(req);

    var body = std.ArrayListUnmanaged(u8).empty;
    defer body.deinit(allocator);

    // discard response headers
    _ = try conn.next();
    while (try conn.next()) |data| {
        try body.appendSlice(allocator, data);
    }

    return try body.toOwnedSlice(allocator);
}
