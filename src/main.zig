const std = @import("std");

const Token = struct {
    type: TokenEnum,
    negative: bool = false,
    is_start_with: bool = false,
    is_end_with: bool = false,
    payload: ?[]const u8 = null,
};
const TokenEnum = enum {
    digit,
    alphanumeric,
    word_group,
    negative,
    char,
};
const TokenizeError = error{
    InvalidPattern,
};
fn tokenize(allocator: std.mem.Allocator, pattern: []const u8) !std.ArrayList(Token) {
    var tokens = std.ArrayList(Token).init(allocator);
    var index: usize = 0;
    var symbol: u8 = undefined;
    var has_start_with_symbol = false;
    while (index < pattern.len) : ({
        index += 1;
    }) {
        if (index < pattern.len) {
            symbol = pattern[index];
        }

        if (symbol == '\\' and index + 1 < pattern.len) {
            const e = pattern[index + 1];
            switch (e) {
                'd' => try tokens.append(.{
                    .type = .digit,
                }),
                'w' => try tokens.append(.{
                    .type = .alphanumeric,
                }),
                else => {},
            }

            if (index + 1 < pattern.len) {
                index += 1;
            }
            continue;
        }
        if (symbol == '[' and index + 1 < pattern.len) {
            var slice = pattern[index + 1 ..];
            var negative_flag = false;
            if (index + 1 < pattern.len and pattern[index + 1] == '^') {
                negative_flag = true;
                index += 1;
                slice = pattern[index + 1 ..];
            }
            const closed_pos = std.mem.indexOfScalar(u8, slice, ']') orelse return TokenizeError.InvalidPattern;
            const char_slice = slice[0..closed_pos];
            if (char_slice.len == 0) return TokenizeError.InvalidPattern;
            var string = std.ArrayList(u8).init(allocator);
            for (char_slice) |char| {
                try string.append(char);
            }
            try tokens.append(.{
                .type = .word_group,
                .payload = string.items,
                .negative = negative_flag,
            });
            index += char_slice.len + 1;
            continue;
        }
        if (symbol == '^' and index + 1 < pattern.len) {
            if (has_start_with_symbol) {
                return TokenizeError.InvalidPattern;
            }
            if (std.ascii.isAlphabetic(pattern[index + 1])) {
                try tokens.append(.{
                    .type = .char,
                    .payload = pattern[index + 1 .. index + 2],
                    .is_start_with = true,
                });
                index += 1;
                has_start_with_symbol = true;
                continue;
            } else {
                return TokenizeError.InvalidPattern;
            }
        }
        if (symbol == '$') {
            if (index != pattern.len - 1) {
                return TokenizeError.InvalidPattern;
            }
            tokens.items[tokens.items.len - 1].is_end_with = true;
            continue;
        }
        try tokens.append(.{ .type = .char, .payload = pattern[index .. index + 1] });
    }
    return tokens;
}
fn isDigit(char: u8) bool {
    return char >= '0' and char <= '9';
}
fn matchPattern(input_line: []const u8, pattern: []const u8) !bool {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tokens = try tokenize(allocator, pattern);
    std.debug.print("\ntokens: {any}\n\n", .{tokens.items});
    var char_index: usize = 0;
    var token_index: usize = 0;
    const matched = while (token_index < tokens.items.len) : (char_index += 1) {
        if (char_index >= input_line.len) {
            break false;
        }
        const token = tokens.items[token_index];
        const current_char = input_line[char_index];

        std.debug.print("\ni: {d},{d}\n", .{ token_index, char_index });
        std.debug.print("c: {any},{c}\n", .{ token.type, current_char });
        switch (token.type) {
            .char => {
                std.debug.print("\nc: {d},{d}\n", .{ current_char, token.payload.?[0] });
                if (current_char == token.payload.?[0]) {
                    if (token.is_start_with and char_index != 0) {
                        break false;
                    }
                    if (token.is_end_with and char_index != input_line.len - 1) {
                        break false;
                    }
                    token_index += 1;
                    continue;
                } else {
                    if (token_index == 0 and token_index != tokens.items.len - 1) {
                        continue;
                    }
                    break false;
                }
            },
            .digit => {
                if (isDigit(current_char)) {
                    if (char_index + 1 < input_line.len) {
                        token_index += 1;
                    }
                    continue;
                } else {
                    if (token_index == 0 and token_index != tokens.items.len - 1) {
                        continue;
                    }
                    break false;
                }
            },
            .alphanumeric => {
                if (std.ascii.isAlphanumeric(current_char) or current_char == '_') {
                    token_index += 1;
                    continue;
                } else {
                    if (token_index == 0 and token_index != tokens.items.len - 1) {
                        continue;
                    }
                    break false;
                }
            },
            .word_group => {
                const result = for (token.payload.?) |c| {
                    const contains_char = std.mem.containsAtLeastScalar(u8, input_line, 1, c);
                    if (token.negative and !contains_char) {
                        break true;
                    }
                    if (!token.negative and contains_char) {
                        break true;
                    }
                } else false;
                if (result) {
                    token_index += 1;
                    continue;
                }
                if (token_index == 0 and token_index != tokens.items.len - 1) {
                    continue;
                }
                break false;
            },
            else => break false,
        }
        if (token.is_end_with and char_index != input_line.len - 1) {
            break false;
        }
    } else true;
    return matched;
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
    if (try matchPattern(input_slice, pattern)) {
        std.debug.print("matched", .{});
        std.process.exit(0);
    } else {
        std.debug.print("not matched", .{});
        std.process.exit(1);
    }
}
