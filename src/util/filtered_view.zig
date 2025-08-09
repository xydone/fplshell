pub fn FilteredView(comptime T: type, comptime predicate: fn (*const T, []const u8) bool) type {
    return struct {
        items: []const T,
        index: usize = 0,

        pub fn init(items: []const T) @This() {
            return .{ .items = items, .index = 0 };
        }

        pub fn next(self: *@This(), phrase: []const u8) ?*const T {
            while (self.index < self.items.len) {
                const item_ptr = &self.items[self.index];
                self.index += 1;
                if (predicate(item_ptr, phrase)) {
                    return item_ptr;
                }
            }
            return null;
        }
        pub fn reset(self: *@This()) void {
            self.index = 0;
        }
    };
}
