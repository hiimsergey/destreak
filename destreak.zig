const std = @import("std");

const Allocator = std.mem.Allocator;
const AllocatorWrapper = @import("allocator.zig").AllocatorWrapper;
const Dir = std.fs.Dir;
const File = std.fs.File;

const stderr = std.io.getStdErr().writer();
const stdout = std.io.getStdOut().writer();

inline fn eql(a: []const u8, b: []const u8) bool {
	return std.mem.eql(u8, a, b);
}

inline fn println(comptime fmt: []const u8, args: anytype) void {
	stdout.print(fmt ++ "\n", args) catch {};
}

inline fn errln(comptime msg: []const u8) void {
	stderr.print(msg ++ "\n", .{}) catch {};
}

pub fn main() !void {
	var aw = AllocatorWrapper.init();
	defer aw.deinit();
	const allocator = aw.allocator();

	var args = std.process.args();

	_ = args.next(); // Skips executable name
	const arg1 = args.next();

	if (arg1 == null) try list(allocator)
	else if (eql(arg1.?, "--new") or eql(arg1.?, "-n")) try new(allocator, args.next())
	else if (eql(arg1.?, "--delete") or eql(arg1.?, "-d")) try delete(allocator, args.next())
	else if (arg1.?[0] == '-') {
		help();
		return error.Help;
	}
	else destreak(arg1.?);

	// TODO PLAN args
	// destreak
	// destreak something
	// destreak --new something
	// destreak --delete something
	// destreak --help
	// destreak --ErOrR
}

fn open_datafile(allocator: Allocator) !File {
	const dirpath = std.process.getEnvVarOwned(allocator, "XDG_DATA_HOME") catch blk: {
		const home = try std.process.getEnvVarOwned(allocator, "HOME");
		defer allocator.free(home);
		break :blk try std.mem.concat(allocator, u8, &.{ home, "/.local/share"});
	};
	defer allocator.free(dirpath);

	const dir: Dir = try std.fs.openDirAbsolute(dirpath, .{});
	return try dir.createFile("datastreak.bin", .{
		.read = true,
		.truncate = false
	});
}

fn list(allocator: Allocator) !void {
	var datafile: File = try open_datafile(allocator);
	defer datafile.close();

	const reader = datafile.reader();

	while (true) {
		const len_decr: u8 = reader.readByte() catch break;

		const buf = try allocator.alloc(u8, len_decr + 1);
		defer allocator.free(buf);

		const streak = try reader.readInt(u64, .little);

		println("{d:>4}  {s}", .{streak, buf});
	}
}

fn new(allocator: Allocator, entry: ?[]const u8) !void {
	_ = allocator;
	_ = entry;
}

fn delete(allocator: Allocator, entry: ?[]const u8) !void {
	_ = allocator;
	_ = entry;
}

fn help() void {}

fn destreak(entry: ?[]const u8) void {
	_ = entry;
}
