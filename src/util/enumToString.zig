const std = @import("std");

pub fn enumToString(comptime T: type) []const u8 {
    return comptime blk: {
        var total_len: usize = 0;
        const border = " | ";
        const start = "<";
        const end = ">";

        const fields = @typeInfo(T).@"enum".fields;
        if (fields.len == 0) {
            break :blk "";
        }

        total_len += start.len;
        total_len += end.len;

        for (fields, 0..) |field, i| {
            total_len += field.name.len;
            if (i < fields.len - 1) {
                total_len += border.len;
            }
        }

        var buf: [total_len]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buf);

        try fbs.writer().print("<", .{});
        for (fields, 0..) |field, i| {
            try fbs.writer().print("{s}", .{field.name});
            if (i < fields.len - 1) {
                try fbs.writer().print(border, .{});
            }
        }
        try fbs.writer().print(">", .{});

        // copy to const to avoid compiler complaining about global variable with pointer to comptime var
        const text = buf;
        break :blk &text;
    };
}
