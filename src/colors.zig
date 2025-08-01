const std = @import("std");
const vaxis = @import("vaxis");
pub const Color = vaxis.Cell.Color;

pub const light_blue: Color = .{ .rgb = .{ 50, 133, 166 } };

pub const black: Color = .{ .rgb = .{ 0, 0, 0 } };
pub const white: Color = .{ .rgb = .{ 255, 255, 255 } };

pub const gray: Color = .{ .rgb = .{ 12, 12, 12 } };
pub const light_gray: Color = .{ .rgb = .{ 8, 8, 8 } };

pub fn getTextColor(color: Color) Color {
    const r = color.rgb[0];
    const g = color.rgb[1];
    const b = color.rgb[2];
    const rf = @as(f64, @floatFromInt(r)) / 255.0;
    const gf = @as(f64, @floatFromInt(g)) / 255.0;
    const bf = @as(f64, @floatFromInt(b)) / 255.0;

    const GammaCorrection = struct {
        pub fn apply(c: f64) f64 {
            return if (c <= 0.03928) c / 12.92 else std.math.pow(f64, (c + 0.055) / 1.055, 2.4);
        }
    };

    const r_lin = GammaCorrection.apply(rf);
    const g_lin = GammaCorrection.apply(gf);
    const b_lin = GammaCorrection.apply(bf);

    const L = 0.2126 * r_lin + 0.7152 * g_lin + 0.0722 * b_lin;

    return if (L > 0.179) return black else white;
}

/// Clamped to 255
pub inline fn brighten(color: Color, amount: u8) Color {
    const r: u16 = @intCast(color.rgb[0]);
    const g: u16 = @intCast(color.rgb[1]);
    const b: u16 = @intCast(color.rgb[2]);
    return Color{ .rgb = .{
        @min(r + amount, 255),
        @min(g + amount, 255),
        @min(b + amount, 255),
    } };
}

/// Clamped to 0
pub inline fn darken(color: Color, amount: u8) Color {
    const r: i16 = @intCast(color.rgb[0]);
    const g: i16 = @intCast(color.rgb[1]);
    const b: i16 = @intCast(color.rgb[2]);

    const amt: i16 = @intCast(amount);

    return Color{
        .rgb = .{
            @intCast(@max(0, r - amt)),
            @intCast(@max(0, g - amt)),
            @intCast(@max(0, b - amt)),
        },
    };
}
