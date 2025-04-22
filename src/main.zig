const std = @import("std");

fn matchPattern(input_line: []const u8, pattern: []const u8) bool {
    if (pattern.len == 1) {
        return std.mem.indexOf(u8, input_line, pattern) != null;
    }
    for (pattern, 0..) |symbol, index| {
        if (symbol == '\\' and index + 1 < pattern.len) {
            switch (pattern[index + 1]) {
                'd' => {
                    for (input_line) |char| switch (char) {
                        '0'...'9' => return true,
                        else => {},
                    };
                },
                'w' => {
                    for (input_line) |char| {
                        if (std.ascii.isAlphanumeric(char) or char == '_') {
                            return true;
                        }
                    }
                },
                else => {},
            }
        }
        if (symbol == '[') {
            var slice = pattern[index + 1 ..];
            var char_list: [1024]u8 = undefined;
            var char_index: usize = 0;
            var negative_flag = false;
            var closed_flag = false;
            if (index + 1 < pattern.len and pattern[index + 1] == '^') {
                negative_flag = true;
                slice = pattern[index + 2 ..];
            }
            for (slice) |char| {
                if (char == ']') {
                    closed_flag = true;
                    break;
                }
                if (char_index < char_list.len) {
                    char_list[char_index] = char;
                    char_index += 1;
                }
            }
            std.debug.print("char_list: {s}\n", .{char_list});
            std.debug.print("negative_flag: {any}\n", .{negative_flag});
            if (closed_flag and char_list.len > 0) {
                const result = for (char_list[0..char_index]) |char| {
                    std.debug.print("char: {c}\n", .{char});
                    if (negative_flag) {
                        if (!std.mem.containsAtLeastScalar(u8, input_line, 1, char)) {
                            break true;
                        }
                    } else {
                        if (std.mem.containsAtLeastScalar(u8, input_line, 1, char)) {
                            break true;
                        }
                    }
                } else false;
                std.debug.print("result: {any}\n", .{result});
                return result;
            }
            return false;
        }
    }
    return false;
}

pub fn main() !void {
    var buffer: [1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = fba.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 3 or !std.mem.eql(u8, args[1], "-E")) {
        std.debug.print("Expected first argument to be '-E'\n", .{});
        std.process.exit(1);
    }

    std.debug.print("Logs from your program will appear here!\n", .{});

    const pattern = args[2];
    var input_line: [1024]u8 = undefined;
    const input_len = try std.io.getStdIn().reader().read(&input_line);
    const input_slice = input_line[0..input_len];
    if (matchPattern(input_slice, pattern)) {
        std.debug.print("ok", .{});
        std.process.exit(0);
    } else {
        std.debug.print("err", .{});
        std.process.exit(1);
    }
}
