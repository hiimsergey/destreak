const std = @import("std");
const main = @import("main.zig");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const File = std.fs.File;

const StreakList = struct {
	const Streak = struct { name: []u8, time: i64 };

	list: ArrayList(Streak),

	pub fn deinit(self: *StreakList, allocator: Allocator) void {
		for (self.list.items) |item| allocator.free(item.name);
		self.list.deinit(allocator);
	}
};

pub fn open_datafile(allocator: Allocator) !File {
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

pub fn parse(allocator: Allocator, datafile: File) !StreakList {
	var buf: [1024]u8 = undefined;
	var reader = datafile.reader(&buf);

	var result = StreakList{ .list = .empty };

	var len_decr: u8 = undefined;
	parsing: while (true) {
		_ = reader.read(@ptrCast(&len_decr)) catch |err| {
			if (err == error.EndOfStream) break :parsing;
			return err;
		};

		var item = StreakList.Streak{
			.name = try allocator.alloc(u8, len_decr + 1),
			.time = undefined
		};

		_ = try reader.read(item.name);
		_ = try reader.read(@ptrCast(&item.time));

		try result.list.append(allocator, item);
	}

	return result;
}

pub fn delete_entry(allocator: Allocator, datafile: File, entry: []const u8) !void {
	var reader_buf: [1024]u8 = undefined;
	var reader = datafile.reader(&reader_buf);

	var writer_buf: [1024]u8 = undefined;
	var writer = datafile.writer(&writer_buf);

	const entry_buf = try allocator.alloc(u8, entry.len);
	defer allocator.free(entry_buf);

	var len_decr: u8 = undefined;
	while (true) {
		_ = reader.read(@ptrCast(&len_decr)) catch |err| {
			if (err == error.EndOfStream) break;
			return err;
		};
		if (len_decr + 1 != entry.len) {
			try reader.seekBy(@intCast(len_decr + 1 + @sizeOf(i64)));
			continue;
		}
		_ = try reader.read(entry_buf);
		if (!main.eql(entry_buf, entry)) {
			try reader.seekBy(@intCast(@sizeOf(i64)));
			continue;
		}

		writer.seekTo(reader.pos - @sizeOf(u8) - entry.len) catch |err| {
			main.errln("TODO 3", .{});
			return err;
		};
		var copy_buf: [4096]u8 = undefined;
		var n: usize = undefined;
		while (true) {
			n = try reader.read(&copy_buf);
			if (n == 0) break;
			_ = try writer.interface.write(copy_buf[0..n]);
		}
		try writer.interface.flush();
		try datafile.setEndPos(writer.pos);
		return;
	}

	main.errln("No such activity '{s}'", .{entry});
}
