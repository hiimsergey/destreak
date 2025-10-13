const std = @import("std");

const Allocator = std.mem.Allocator;
const AllocatorWrapper = @import("allocator.zig").AllocatorWrapper;

var stderr_buf: [256]u8 = undefined;
var stdout_buf: [256]u8 = undefined;
var stderr = std.fs.File.stderr().writer(&stderr_buf);
var stdout = std.fs.File.stdout().writer(&stdout_buf);

pub fn eql(a: []const u8, b: []const u8) bool {
	return std.mem.eql(u8, a, b);
}
pub fn errln(comptime msg: []const u8, args: anytype) void {
	stderr.interface.print("\x1b[31m" ++ msg ++ "\n", args) catch {};
	stderr.interface.flush() catch {};
}
fn println(comptime fmt: []const u8, args: anytype) void {
	stdout.interface.print(fmt ++ "\n", args) catch {};
}

fn open_datafile(allocator: Allocator) !std.fs.File {
	const dirpath = std.process.getEnvVarOwned(allocator, "XDG_DATA_HOME") catch blk: {
		const home = try std.process.getEnvVarOwned(allocator, "HOME");
		defer allocator.free(home);
		break :blk try std.mem.concat(allocator, u8, &.{home, "/.local/share"});
	};
	defer allocator.free(dirpath);

	var dir = try std.fs.openDirAbsolute(dirpath, .{});
	defer dir.close();

	return try dir.createFile("destreak.bin", .{ .read = true, .truncate = false });
}

fn list(allocator: Allocator) !void {
	var file = try open_datafile(allocator);
	defer file.close();

	var reader_buf: [128]u8 = undefined;
	var reader = file.reader(&reader_buf);

	const now = std.time.timestamp();
	var len_minus_one: u8 = undefined;
	var title: []u8 = &.{};
	defer allocator.free(title);
	var timestamp: i64 = undefined;
	while (true) {
		_ = reader.readPositional(@ptrCast(&len_minus_one)) catch |err| switch (err) {
			error.EndOfStream => break,
			else => return err
		};
		title = try allocator.realloc(title, len_minus_one + 1);
		_ = try reader.readPositional(title);

		_ = try reader.readPositional(@ptrCast(&timestamp));
		const days_since: u32 =
			@intCast(@divFloor(now - timestamp, std.time.s_per_day));

		println("{d:>4}  {s}", .{days_since, title});
	}
}

fn new(allocator: Allocator, entry: ?[]const u8) !void {
	if (entry == null) {
		errln("Usage: destreak new <activity>", .{});
		return error.Generic;
	}
	if (entry.?.len == 0 or entry.?.len > 256) {
		errln("Invalid name length! It should be between 1 and 256 bytes", .{});
		return error.Generic;
	}

	var file = try open_datafile(allocator);
	defer file.close();

	var reader = file.reader(&.{});

	// Check if entry already exists
	var len_minus_one: u8 = undefined;
	const title = try allocator.alloc(u8, entry.?.len);
	defer allocator.free(title);
	while (true) {
		_ = reader.readPositional(@ptrCast(&len_minus_one)) catch |err| switch (err) {
			error.EndOfStream => break,
			else => return err
		};
		if (len_minus_one + 1 != entry.?.len) {
			try reader.seekBy(@intCast(len_minus_one + 1 + @sizeOf(i64)));
			continue;
		}
		_ = try reader.readPositional(title);
		if (eql(title, entry.?)) {
			errln("'{s}' is already registered!", .{entry.?});
			return error.Generic;
		}
		try reader.seekBy(@intCast(@sizeOf(i64)));
	}

	// Actually add entry
	const now = std.time.timestamp();

	var writer_buf: [32]u8 = undefined;
	var writer = file.writer(&writer_buf);
	try writer.seekTo(reader.pos);

	try writer.interface.writeByte(@intCast(entry.?.len - 1));
	_ = try writer.interface.write(entry.?);
	try writer.interface.writeInt(i64, now, .little);

	try writer.interface.flush();
	return list(allocator);
}

fn delete(allocator: Allocator, entry: ?[]const u8) !void {
	if (entry == null) {
		errln("Usage: destreak new <activity>", .{});
		return error.Generic;
	}
	if (entry.?.len == 0 or entry.?.len > 256) {
		errln("Invalid name length! It should be between 1 and 256 bytes", .{});
		return error.Generic;
	}

	var file = try open_datafile(allocator);
	defer file.close();

	var reader = file.reader(&.{});
	var writer = file.writer(&.{});

	const title = try allocator.alloc(u8, entry.?.len);
	defer allocator.free(title);

	// Check if entry exists at all
	var len_minus_one: u8 = undefined;
	while (true) {
		_ = reader.readPositional(@ptrCast(&len_minus_one)) catch {
			errln("No such activity '{s}'!", .{entry.?});
			return error.Generic;
		};
		if (len_minus_one + 1 != entry.?.len) {
			try reader.seekBy(@intCast(len_minus_one + 1 + @sizeOf(i64)));
			continue;
		}
		_ = try reader.readPositional(title);
		try reader.seekBy(@intCast(@sizeOf(i64)));

		if (eql(title, entry.?)) break;
	}

	const file_size: usize = @intCast(try file.getEndPos());
	const record_len: usize = @sizeOf(u8) + title.len + @sizeOf(i64);
	try writer.seekTo(reader.pos - record_len);

	// Actually delete entry
	var copy_buf: [32]u8 = undefined;
	var n: usize = undefined;
	while (true) {
		n = reader.read(&copy_buf) catch |err| switch (err) {
			error.EndOfStream => break,
			else => return err
		};
		_ = try writer.interface.write(copy_buf[0..n]);
	}

	try file.setEndPos(file_size - record_len);
	return list(allocator);
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
		\\    v0.1.0  GPL-3.0 license
		\\    by Sergey Lavrent
		\\    https://github.com/hiimsergey/destreak
		, .{}
	);
}

fn reset(allocator: Allocator, arg: []const u8) !void {
	var file = try open_datafile(allocator);
	defer file.close();

	var reader = file.reader(&.{});
	var writer = file.writer(&.{});

	const title = try allocator.alloc(u8, arg.len);
	defer allocator.free(title);

	// Check if entry exists at all
	var len_minus_one: u8 = undefined;
	while (true) {
		_ = reader.readPositional(@ptrCast(&len_minus_one)) catch {
			errln("No such activity '{s}'!", .{arg});
			return error.Generic;
		};
		if (len_minus_one + 1 != arg.len) {
			try reader.seekBy(@intCast(len_minus_one + 1 + @sizeOf(i64)));
			continue;
		}
		_ = try reader.readPositional(title);
		if (eql(title, arg)) break;
	}

	try writer.seekTo(reader.pos);
	try writer.interface.writeInt(i64, std.time.timestamp(), .little);
	try writer.interface.flush();

	return list(allocator);
}

pub fn main() u8 {
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
		} else if (std.mem.startsWith(u8, arg, "--")) {
			errln(
				"Invalid subcommand '{s}'!\nSee 'destreak help' for correct usage!",
				.{arg}
			);
			return 1;
		} else reset(allocator, arg) catch return 1;
	} else list(allocator) catch return 1;

	stdout.interface.flush() catch {};
	return 0;
}
