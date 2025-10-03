const std = @import("std");

const Allocator = std.mem.Allocator;
const AllocatorWrapper = @import("allocator.zig").AllocatorWrapper;
const data = @import("data.zig");

var stderr_buf: [1024]u8 = undefined;
var stdout_buf: [1024]u8 = undefined;
var stderr = std.fs.File.stderr().writer(&stderr_buf);
var stdout = std.fs.File.stdout().writer(&stdout_buf);

pub fn eql(a: []const u8, b: []const u8) bool {
	return std.mem.eql(u8, a, b);
}
fn println(comptime fmt: []const u8, args: anytype) void {
	stdout.interface.print(fmt ++ "\n", args) catch {};
}
pub fn errln(comptime msg: []const u8, args: anytype) void {
	stderr.interface.print("\x1b[31m" ++ msg ++ "\n", args) catch {};
	stderr.interface.flush() catch {};
}

fn list(allocator: Allocator) !void {
	var datafile = try data.open_datafile(allocator);
	defer datafile.close();

	var streaks = try data.parse(allocator, datafile);
	defer streaks.deinit(allocator);

	const now = std.time.timestamp();

	for (streaks.list.items) |item| {
		const days_since: usize =
			@intCast(@divFloor(now - item.time, std.time.s_per_day));
		println("{d:>4}  {s}", .{days_since, item.name});
	}
}

fn new(allocator: Allocator, entry: ?[]const u8) !void {
	if (entry == null) {
		errln("Usage: destreak new <activity>", .{});
		return error.Generic;
	}
	if (entry.?.len > 256) {
		errln("Argument name too long! The maximum allowed length is 256 bytes.", .{});
		return error.Generic;
	}

	var datafile = try data.open_datafile(allocator);
	defer datafile.close();

	var streaks = try data.parse(allocator, datafile);
	defer streaks.deinit(allocator);

	for (streaks.list.items) |item| if (eql(item.name, entry.?)) {
		errln("'{s}' is already registered!", .{item.name});
		return error.Generic;
	};

	const now = std.time.timestamp();

	var writer_buf: [1024]u8 = undefined;
	var writer = datafile.writer(&writer_buf);
	try writer.seekTo(try datafile.getEndPos());
	try writer.interface.writeByte(@intCast(entry.?.len - 1));
	_ = try writer.interface.write(entry.?);
	try writer.interface.writeInt(i64, now, .little);
	try writer.interface.flush();
}

fn delete(allocator: Allocator, entry: ?[]const u8) !void {
	if (entry == null) {
		errln("Usage: destreak new <activity>", .{});
		return error.Generic;
	}
	if (entry.?.len > 256) {
		errln("Argument name too long! The maximum allowed length is 256 bytes.", .{});
		return error.Generic;
	}

	var datafile = try data.open_datafile(allocator);
	defer datafile.close();

	return try data.delete_entry(allocator, datafile, entry.?);
}

fn help() void {
	println(
		\\destreak – the bare minimum attempt at gamification
		\\
		\\Usage:
		\\    destreak                        list all registered activities
		\\    destreak <activity>             reset the streak of one activity
		\\    destreak --new <activity>       add a new activity
		\\    destreak --delete <activity>    remove an activity
		\\    destreak --help                 print this message
		\\
		\\Data storage:
		\\    either $XDG_DATA_HOME/destreak.bin
		\\    or $HOME/.local/share/destreak.bin
		\\
		\\About:
		\\    v0.0.0  GPL-3.0 license
		\\    by Sergey Lavrent
		\\    https://github.com/hiimsergey/destreak
		, .{}
	);
}

pub fn main() u8 {
	defer stdout.interface.flush() catch {};

	var aw = AllocatorWrapper.init();
	defer aw.deinit();
	const allocator = aw.allocator();

	var args = std.process.args();

	_ = args.skip(); // skip executable name
	const arg1 = args.next();

	if (arg1) |arg| {
		if (eql(arg, "--new") or eql(arg, "-n"))
			new(allocator, args.next()) catch return 1
		else if (eql(arg, "--delete") or eql(arg, "-d"))
			delete(allocator, args.next()) catch return 1
		else if (eql(arg, "--help") or eql(arg, "-h")) {
			help();
			return 1;
		} else {
			errln(
				"Invalid subcommand '{s}'!\nSee 'destreak help' for correct usage!",
				.{arg}
			);
			return 1;
		}
	} else list(allocator) catch return 1;
	return 0;
}
