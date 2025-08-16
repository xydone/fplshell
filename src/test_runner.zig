//! Fork of https://gist.github.com/karlseguin/c6bea5b35e4e8d26af6f81c22cb5d76b

const std = @import("std");
const builtin = @import("builtin");

const Allocator = std.mem.Allocator;

const BORDER = "=" ** 80;

var current_test: ?[]const u8 = null;
var benchmark_list = std.ArrayList(Benchmark).init(std.heap.smp_allocator);

const Config = struct {
    verbose: bool,
    fail_first: bool,
    filter: ?[]const u8,

    pub fn init() Config {
        return Config{
            .verbose = false,
            .fail_first = false,
            .filter = null,
        };
    }
};

const TestStats = struct {
    pass: u64,
    fail: u64,
    skip: u64,
    leak: u64,
    setup_teardown: u64,

    pub fn init() TestStats {
        return TestStats{
            .pass = 0,
            .fail = 0,
            .skip = 0,
            .leak = 0,
            .setup_teardown = 0,
        };
    }
};

const TestList = struct {
    test_functions: *std.ArrayList(std.builtin.TestFn),
    callback: *const fn (CallbackParams) anyerror!void,

    pub const CallbackType = enum { basic, @"test" };
    pub const CallbackParams = struct { t: std.builtin.TestFn, config: Config, printer: Printer, test_stats: *TestStats };

    pub fn init(allocator: std.mem.Allocator, callback_type: CallbackType) TestList {
        const list = allocator.create(std.ArrayList(std.builtin.TestFn)) catch @panic("cannot allocate arraylist");
        list.* = std.ArrayList(std.builtin.TestFn).init(allocator);
        return TestList{
            .test_functions = list,
            .callback = switch (callback_type) {
                .basic => basic_callback,
                .@"test" => test_callback,
            },
        };
    }

    pub fn deinit(self: TestList, allocator: std.mem.Allocator) void {
        self.test_functions.deinit();
        allocator.destroy(self.test_functions);
    }

    pub fn basic_callback(params: CallbackParams) !void {
        params.t.func() catch |err| {
            return err;
        };
    }
    pub fn test_callback(params: CallbackParams) !void {
        const is_unnamed_test = isUnnamed(params.t);
        if (params.config.filter) |f| {
            if (!is_unnamed_test and std.mem.indexOf(u8, params.t.name, f) == null) {
                // continue;
                return;
            }
        }

        std.testing.allocator_instance = .{};
        const result = params.t.func();

        if (std.testing.allocator_instance.deinit() == .leak) {
            params.test_stats.leak += 1;
        }

        if (result) |_| {
            params.test_stats.pass += 1;
        } else |err| switch (err) {
            error.SkipZigTest => {
                params.test_stats.skip += 1;
            },
            else => {
                params.test_stats.fail += 1;
                if (@errorReturnTrace()) |trace| {
                    params.printer.status(.fail, "{s}\n", .{BORDER});
                    params.printer.status(.fail, "TRACE:\n", .{});
                    std.debug.dumpStackTrace(trace.*);
                    params.printer.status(.fail, "{s}\n", .{BORDER});
                }
            },
        }
    }
};
pub fn main() !void {
    const printer = Printer.init();

    const allocator = std.heap.smp_allocator;

    var config = Config.init();

    const process_args = try std.process.argsAlloc(allocator);
    for (process_args) |arg| {
        if (std.mem.eql(u8, arg, "--verbose")) config.verbose = true;
        if (std.mem.eql(u8, arg, "--fail-first")) config.fail_first = true;
        if (std.mem.startsWith(u8, arg, "--filter")) {
            var tokens = std.mem.tokenizeSequence(u8, arg, "=");
            //skip "--filter"
            _ = tokens.next();
            const filter = tokens.next() orelse return;
            config.filter = filter;
        }
    }

    var test_stats = TestStats.init();
    var timer = std.time.Timer.start() catch @panic("Timer not supported.");

    const setup_queue = TestList.init(allocator, .basic);
    defer setup_queue.deinit(allocator);
    const teardown_queue = TestList.init(allocator, .basic);
    defer teardown_queue.deinit(allocator);
    const tests_queue = TestList.init(allocator, .@"test");
    defer tests_queue.deinit(allocator);

    for (builtin.test_functions) |t| {
        const name = makeNameFriendly(t.name);

        if (isSetup(name)) {
            try setup_queue.test_functions.append(t);
            test_stats.setup_teardown += 1;
            continue;
        }
        if (isTeardown(name)) {
            try teardown_queue.test_functions.append(t);
            test_stats.setup_teardown += 1;
            continue;
        }
        try tests_queue.test_functions.append(t);
    }

    // Order is:
    // 1. Setup
    // 2. Every test
    // 3. Teardown
    const test_run_order = [_]TestList{ setup_queue, tests_queue, teardown_queue };
    for (test_run_order) |list| {
        for (list.test_functions.items) |t| {
            current_test = t.name;
            const params = TestList.CallbackParams{ .config = config, .printer = printer, .test_stats = &test_stats, .t = t };
            try list.callback(params);
        }
    }

    printer.fmt("\n{s}\n", .{BORDER});
    const total_tests = builtin.test_functions.len - test_stats.setup_teardown;
    const total_tests_executed = test_stats.pass + test_stats.fail;
    const not_executed = total_tests - total_tests_executed;
    const has_leaked = test_stats.leak != 0;
    const total_time: f64 = @as(f64, @floatFromInt(timer.lap())) / 1_000_000.0;
    printer.status(.text, "{s: <15}: {d:.3}ms\n", .{ "TOTAL TIME", total_time });
    printer.status(.text, "{s: <15}: {d}\n", .{ "TOTAL EXECUTED", total_tests_executed });
    printer.status(.pass, "{s: <15}: {d}\n", .{ "PASS", test_stats.pass });
    printer.status(.fail, "{s: <15}: {d}\n", .{ "FAILED", test_stats.fail });
    if (not_executed > 0) printer.status(.fail, "{s: <15}: {d}\n", .{ "NOT EXECUTED", not_executed });
    if (has_leaked) printer.status(.fail, "{s: <15}: {d}\n", .{ "LEAKED", test_stats.leak });

    std.posix.exit(if (test_stats.fail == 0) 0 else 1);
}

pub const panic = std.debug.FullPanic(struct {
    pub fn panicFn(msg: []const u8, first_trace_addr: ?usize) noreturn {
        if (current_test) |ct| {
            std.debug.print("\x1b[31m{s}\npanic running \"{s}\"\n{s}\x1b[0m\n", .{ BORDER, ct, BORDER });
        }
        std.debug.defaultPanic(msg, first_trace_addr);
    }
}.panicFn);

fn makeNameFriendly(name: []const u8) []const u8 {
    var it = std.mem.splitScalar(u8, name, '.');
    while (it.next()) |value| {
        if (std.mem.eql(u8, value, "test")) {
            const rest = it.rest();
            return if (rest.len > 0) rest else name;
        }
    }
    return name;
}

fn isUnnamed(t: std.builtin.TestFn) bool {
    const marker = ".test_";
    const test_name = t.name;
    const index = std.mem.indexOf(u8, test_name, marker) orelse return false;
    _ = std.fmt.parseInt(u32, test_name[index + marker.len ..], 10) catch return false;
    return true;
}

fn isSetup(test_name: []const u8) bool {
    return std.mem.endsWith(u8, test_name, "tests:beforeAll");
}

fn isTeardown(test_name: []const u8) bool {
    return std.mem.endsWith(u8, test_name, "tests:afterAll");
}

fn isNotTimed(test_name: []const u8) bool {
    return std.mem.endsWith(u8, test_name, "tests:noTime");
}
fn isAPI(test_name: []const u8) bool {
    return std.mem.startsWith(u8, test_name, "API");
}
fn isEndpoint(test_name: []const u8) bool {
    return std.mem.startsWith(u8, test_name, "Endpoint");
}

pub const Benchmark = struct {
    name: []const u8,
    timer: std.time.Timer,
    status: Status,
    err: ?anyerror = null,
    time_ms: ?f64 = null,

    pub fn start(name: []const u8) Benchmark {
        return .{
            .name = name,
            .timer = std.time.Timer.start() catch @panic("Could not start timer."),
            .status = .pass,
        };
    }

    fn printPass(self: Benchmark, printer: Printer) void {
        printer.status(.pass, "{s} ({d:.2}ms)\n", .{ self.name, self.time_ms.? });
    }

    /// Assumes err is populated
    fn printFail(self: Benchmark, printer: Printer) void {
        printer.status(.fail, "\"{s}\" - {s}\n", .{ self.name, @errorName(self.err.?) });
    }

    pub fn end(self: *Benchmark) void {
        const time = self.timer.lap();

        const printer = Printer.init();
        const ms = @as(f64, @floatFromInt(time)) / 1_000_000.0;
        self.time_ms = ms;
        switch (self.status) {
            .pass => {
                self.printPass(printer);
                benchmark_list.append(self.*) catch @panic("OOM!");
            },
            .fail => {
                self.printFail(printer);
            },
            else => {},
        }
    }

    /// Meant to be called with an errdefer
    pub fn fail(self: *Benchmark, err: anyerror) void {
        self.status = .fail;
        self.err = err;
    }

    /// Meant to be called at the end, after all tests have been executed.
    ///
    /// Should be used inside a tests:afterAll
    pub fn analyze(allocator: std.mem.Allocator) void {
        const list_length = benchmark_list.items.len;

        // early exit if zero tests pass
        if (list_length == 0) return;

        const printer = Printer.init();

        var api_queue = std.ArrayList(Benchmark).init(allocator);
        defer api_queue.deinit();
        var endpoint_queue = std.ArrayList(Benchmark).init(allocator);
        defer endpoint_queue.deinit();

        for (benchmark_list.items) |benchmark| {
            if (isAPI(benchmark.name)) {
                api_queue.append(benchmark) catch @panic("OOM!");
            } else {
                if (isEndpoint(benchmark.name)) {
                    endpoint_queue.append(benchmark) catch @panic("OOM!");
                }
            }
        }

        const BenchmarkType = struct {
            name: []const u8,
            items: []Benchmark,
        };
        const benchmark_map = [_]BenchmarkType{
            BenchmarkType{ .name = "API", .items = api_queue.items },
            BenchmarkType{ .name = "Endpoint", .items = endpoint_queue.items },
            BenchmarkType{ .name = "Total", .items = benchmark_list.items },
        };

        for (benchmark_map) |benchmark_type| {
            // skip benchmark type if empty
            if (benchmark_type.items.len == 0) continue;

            // skip benchmark if it is universal set
            if (benchmark_type.items.len == benchmark_list.items.len and !std.mem.eql(u8, benchmark_type.name, "Total")) continue;

            //calculate runtime of group
            var total_runtime: f64 = 0;
            for (benchmark_type.items) |benchmark| {
                total_runtime += benchmark.time_ms.?;
            }

            printer.fmt("\n{s}\n", .{BORDER});
            printer.fmt("{s} statistics:\n", .{benchmark_type.name});

            //Display runtime of group
            printer.fmt("\nRelevant runtime: {d:.2}ms\n", .{total_runtime});

            //Calculate mean
            const mean = calculateMean(benchmark_type.items);
            printer.fmt("Mean: {d:.2}ms\n", .{mean});

            //Calculate median

            const median = calculateMedian(benchmark_type.items);

            printer.fmt("Median: {d:.2}ms\n", .{median});

            //Display slowest
            printer.fmt("\nSlowest:\n", .{});
            calculateSlowest(5, benchmark_type.items, printer);
        }
    }

    inline fn calculateMean(benchmarks: []Benchmark) f64 {
        var mean: f64 = undefined;
        for (benchmarks) |item| {
            mean += item.time_ms.?;
        }
        return mean / @as(f64, @floatFromInt(benchmarks.len));
    }

    inline fn calculateMedian(benchmarks: []Benchmark) f64 {
        std.mem.sort(Benchmark, benchmarks, {}, Benchmark.moreThan);
        if (benchmarks.len % 2 == 0) {
            const middle1 = benchmarks[benchmarks.len / 2 - 1];
            const middle2 = benchmarks[benchmarks.len / 2];
            return (middle1.time_ms.? + middle2.time_ms.?) / 2;
        } else {
            return benchmarks[benchmarks.len / 2].time_ms.?;
        }
    }

    // need to pass in printer in here to avoid allocations
    inline fn calculateSlowest(amount: u16, benchmarks: []Benchmark, printer: Printer) void {
        for (0..amount) |i| {
            if (i == benchmarks.len) break;
            const benchmark = benchmarks[i];
            // mirrors `.printPass(...)` except uses `Status.text` for color
            printer.status(.text, "{s} ({d:.2}ms)\n", .{ benchmark.name, benchmark.time_ms.? });
        }
    }

    fn moreThan(context: void, a: Benchmark, b: Benchmark) bool {
        _ = context;
        return a.time_ms.? > b.time_ms.?;
    }
};

pub const Printer = struct {
    out: std.fs.File.Writer,

    pub fn init() Printer {
        return .{
            .out = std.io.getStdErr().writer(),
        };
    }

    pub fn fmt(self: Printer, comptime format: []const u8, args: anytype) void {
        std.fmt.format(self.out, format, args) catch unreachable;
    }

    pub fn status(self: Printer, s: Status, comptime format: []const u8, args: anytype) void {
        const color = switch (s) {
            .pass => "\x1b[32m",
            .fail => "\x1b[31m",
            .skip => "\x1b[33m",
            else => "",
        };
        const out = self.out;
        out.writeAll(color) catch @panic("writeAll failed?!");
        std.fmt.format(out, format, args) catch @panic("std.fmt.format failed?!");
        self.fmt("\x1b[0m", .{});
    }
};
pub const Status = enum {
    pass,
    fail,
    skip,
    text,
};
