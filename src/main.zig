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

pub fn open_datadir(allocator: Allocator) !std.fs.Dir {
	const dirpath = std.process.getEnvVarOwned(allocator, "XDG_DATA_HOME") catch blk: {
		const home = try std.process.getEnvVarOwned(allocator, "HOME");
		defer allocator.free(home);
		break :blk try std.mem.concat(allocator, u8, &.{home, "/.local/share"});
	};
	defer allocator.free(dirpath);

	return try std.fs.openDirAbsolute(dirpath, .{});
}

fn open_datafile(allocator: Allocator) !std.fs.File {
	var dir = try open_datadir(allocator);
	defer dir.close();
	return try dir.createFile("destreak.bin", .{ .read = true, .truncate = false });
}

fn list(allocator: Allocator) !void {
	var file = try open_datafile(allocator);
	defer file.close();

	var reader_buf: [256]u8 = undefined;
	var reader = file.reader(&reader_buf);

	const now = std.time.timestamp();
	var len_decr: u8 = undefined;
	var title: []u8 = &.{};
	defer allocator.free(title);
	var time: i64 = undefined;
	while (true) {
		_ = reader.readPositional(@ptrCast(&len_decr)) catch |err| switch (err) {
			error.EndOfStream => break,
			else => return err
		};
		title = try allocator.realloc(title, len_decr + 1);
		_ = reader.readPositional(title) catch |err| {
			errln("TODO fuck 0 {s}", .{@errorName(err)});
			return err;
		};

		_ = reader.readPositional(@ptrCast(&time)) catch |err| {
			errln("TODO fuck 1", .{});
			return err;
		};
		// TODO FINAL TEST
		const days_since: u32 =
			@intCast(@divFloor(now - time, std.time.s_per_day));

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

	var reader_buf: [32]u8 = undefined;
	var reader = file.reader(&reader_buf);

	// TODO TEST
	// Check if entry already exists
	var len_decr: u8 = undefined;
	const title = try allocator.alloc(u8, entry.?.len);
	defer allocator.free(title);
	while (true) {
		_ = reader.readPositional(@ptrCast(&len_decr)) catch |err| switch (err) {
			error.EndOfStream => break,
			else => return err
		};
		if (len_decr + 1 != entry.?.len) {
			try reader.seekBy(@intCast(len_decr + 1 + @sizeOf(i64)));
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

	var reader_buf: [256]u8 = undefined;
	var writer_buf: [256]u8 = undefined;
	var reader = file.reader(&reader_buf);
	var writer = file.writer(&writer_buf);

	const title = try allocator.alloc(u8, entry.?.len);
	defer allocator.free(title);

	// Check if entry exists at all
	var len_decr: u8 = undefined;
	const size_to_delete: u16 = while (true) {
		_ = reader.readPositional(@ptrCast(&len_decr)) catch {
			errln("No such activity '{s}'", .{entry.?});
			return error.Generic;
		};
		if (len_decr + 1 != entry.?.len) {
			try reader.seekBy(@intCast(len_decr + 1 + @sizeOf(i64)));
			continue;
		}
		_ = try reader.readPositional(title);
		try reader.seekBy(@intCast(@sizeOf(i64)));

		if (eql(title, entry.?)) {
			const result: u16 = @intCast(@sizeOf(u8) + title.len + @sizeOf(i64));
			println("writerpos: {d}", .{writer.pos});
			try writer.seekTo(reader.pos - result);
			println("writerpos: {d} (should be {d})", .{writer.pos, reader.pos - result});
			break result;
		}
	};

	// Actually delete entry
	println("file size before writing: {d}", .{try file.getEndPos()});
	var copy_buf: [32]u8 = undefined;
	var n: usize = undefined;
	while (true) {
		n = reader.readStreaming(&copy_buf) catch |err| switch (err) {
			error.EndOfStream => break,
			else => return err
		};
		_ = try writer.interface.write(copy_buf[0..n]);
	}

	try file.setEndPos(try file.getEndPos() - size_to_delete);
	// TODO NOW NOTE flushing is the problem. it unnecessarily bloats the file. idky
	try writer.interface.flush();
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
