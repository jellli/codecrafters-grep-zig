const std = @import("std");
const testing = std.testing;

fn isDigit(char: u8) bool {
    return char >= '0' and char <= '9';
}

const Token = struct {
    type: Pattern,
    payload: ?[]const u8 = null,
};
const Pattern = enum {
    Digit,
    Char,
    AlphaNumeric,
    PositiveCharGroup,
    NegativeCharGroup,
    StartAnchor,
    EndAnchor,
    OneOrMore,
    ZeroOrOne,
};
const TokenizeError = error{
    InvalidPattern,
};

fn nextChar(text: []const u8, current_index: *usize) ?u8 {
    if (current_index.* + 1 < text.len) {
        current_index.* += 1;
        return text[current_index.*];
    } else {
        return null;
    }
}

fn tokenize(allocator: std.mem.Allocator, pattern: []const u8) !std.ArrayList(Token) {
    var tokens = std.ArrayList(Token).init(allocator);
    var pattern_index: usize = 0;
    var char: u8 = undefined;
    var has_start_anchor = false;
    while (pattern_index < pattern.len) : ({
        pattern_index += 1;
    }) {
        char = pattern[pattern_index];
        switch (char) {
            '\\' => {
                if (nextChar(pattern, &pattern_index)) |next_char| switch (next_char) {
                    'd' => try tokens.append(.{
                        .type = .Digit,
                    }),
                    'w' => try tokens.append(.{
                        .type = .AlphaNumeric,
                    }),
                    else => return TokenizeError.InvalidPattern,
                } else return TokenizeError.InvalidPattern;
            },
            '[' => {
                if (nextChar(pattern, &pattern_index)) |next_char| {
                    var negative_flag = false;
                    if (next_char == '^') {
                        negative_flag = true;
                    }
                    const closed_pos = std.mem.indexOfScalar(u8, pattern[pattern_index..], ']') orelse return TokenizeError.InvalidPattern;
                    const char_slice = pattern[pattern_index..closed_pos];
                    if (char_slice.len == 0) return TokenizeError.InvalidPattern;
                    try tokens.append(.{ .type = if (negative_flag) .NegativeCharGroup else .PositiveCharGroup, .payload = char_slice });
                    pattern_index += char_slice.len + 1;
                } else return TokenizeError.InvalidPattern;
            },
            '^' => {
                if (has_start_anchor) {
                    return TokenizeError.InvalidPattern;
                }
                has_start_anchor = true;
                try tokens.append(.{ .type = .StartAnchor });
            },
            '$' => {
                if (pattern_index != pattern.len - 1) {
                    return TokenizeError.InvalidPattern;
                }
                try tokens.append(.{ .type = .EndAnchor });
            },
            '+' => {
                try tokens.append(.{ .type = .OneOrMore });
            },
            '?' => {
                try tokens.append(.{ .type = .ZeroOrOne });
            },
            else => {
                try tokens.append(.{
                    .type = .Char,
                    .payload = try allocator.dupe(u8, &[_]u8{char}),
                });
                continue;
            },
        }
    }
    return tokens;
}

const Regex = struct {
    allocator: std.mem.Allocator,
    pattern: []const u8,
    tokens: std.ArrayList(Token) = undefined,

    const Self = @This();

    fn init(
        allocator: std.mem.Allocator,
        pattern: []const u8,
    ) !@This() {
        return .{
            .allocator = allocator,
            .pattern = pattern,
            .tokens = try tokenize(allocator, pattern),
        };
    }

    fn match(self: *const Self, target: []const u8) bool {
        var target_index: usize = 0;
        var token_index: usize = 0;
        const result = while (token_index < self.tokens.items.len) {
            if (target_index > target.len) break false;
            var token = self.tokens.items[token_index];
        } else true;
        return result;
    }
};

test "regex plain string tokenize" {
    const allocator = std.heap.page_allocator;
    const pattern = "dog";
    const reg = try Regex.init(allocator, pattern);
    for (reg.tokens.items, "dog") |token, char| {
        try testing.expectEqual(Pattern.Char, token.type);
        try testing.expectEqual(char, token.payload.?[0]);
    }
}

test "regex digit/alphanumeric tokenize" {
    const allocator = std.heap.page_allocator;
    const pattern = "\\d\\w";
    const reg = try Regex.init(allocator, pattern);
    try testing.expect(reg.tokens.items.len == 2);
    try testing.expectEqual(reg.tokens.items[0].type, Pattern.Digit);
    try testing.expectEqual(reg.tokens.items[1].type, Pattern.AlphaNumeric);
}

test "regex positive/negative char group tokenize" {
    const allocator = std.heap.page_allocator;
    const n_pattern = "[^apq]";
    const p_pattern = "[abc]";
    const n_reg = try Regex.init(allocator, n_pattern);
    const p_reg = try Regex.init(allocator, p_pattern);
    try testing.expect(n_reg.tokens.items.len == 1);
    try testing.expect(p_reg.tokens.items.len == 1);
    try testing.expectEqual(n_reg.tokens.items[0].type, Pattern.NegativeCharGroup);
    try testing.expectEqual(p_reg.tokens.items[0].type, Pattern.PositiveCharGroup);
}

// fn matchPattern(input_line: []const u8, pattern: []const u8) !bool {
//     var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
//     defer arena.deinit();
//     const allocator = arena.allocator();
//     const tokens = try tokenize(allocator, pattern);
//     std.debug.print("\ntokens: {any}\n\n", .{tokens.items});
//     var char_index: usize = 0;
//     var token_index: usize = 0;
//     const matched = while (token_index < tokens.items.len) : (char_index += 1) {
//         if (char_index >= input_line.len) {
//             break false;
//         }
//         const token = tokens.items[token_index];
//         const current_char = input_line[char_index];
//
//         std.debug.print("----------------------\ntoken_index: {d}\tchar_index: {d}\n", .{ token_index, char_index });
//         std.debug.print("\ntoken_type: {any}\tcurrent_char: {c}\n", .{ token.type, current_char });
//         switch (token.type) {
//             .char => {
//                 std.debug.print("\ntoken_char: {c}\ttarget_char: {c}\tis_zero_or_one: {any}\n", .{
//                     token.payload.?[0],
//                     current_char,
//                     token.is_zero_or_one,
//                 });
//                 if (current_char == token.payload.?[0]) {
//                     if (token.is_start_with and char_index != 0) {
//                         break false;
//                     }
//                     if (token.is_end_with and char_index != input_line.len - 1) {
//                         break false;
//                     }
//                     if (token.is_one_or_more) {
//                         var stop_flag = false;
//                         if (token_index + 1 < tokens.items.len and token.payload.?[0] == current_char) {
//                             stop_flag = true;
//                         }
//                         while (char_index + 1 < input_line.len and input_line[char_index + 1] == current_char) {
//                             if (stop_flag and char_index + 2 < input_line.len and input_line[char_index + 2] != current_char) {
//                                 break;
//                             }
//                             char_index += 1;
//                         }
//                     }
//                     token_index += 1;
//                     continue;
//                 } else {
//                     if (token.is_zero_or_one) {
//                         token_index += 1;
//                         char_index -= 1;
//                         continue;
//                     }
//                     if (token_index == 0 and token_index != tokens.items.len - 1) {
//                         continue;
//                     }
//                     break false;
//                 }
//             },
//             .digit => {
//                 if (isDigit(current_char)) {
//                     if (char_index + 1 < input_line.len) {
//                         token_index += 1;
//                     }
//                     continue;
//                 } else {
//                     if (token_index == 0 and token_index != tokens.items.len - 1) {
//                         continue;
//                     }
//                     break false;
//                 }
//             },
//             .alphanumeric => {
//                 if (std.ascii.isAlphanumeric(current_char) or current_char == '_') {
//                     token_index += 1;
//                     continue;
//                 } else {
//                     if (token_index == 0 and token_index != tokens.items.len - 1) {
//                         continue;
//                     }
//                     break false;
//                 }
//             },
//             .word_group => {
//                 const result = for (token.payload.?) |c| {
//                     const contains_char = std.mem.containsAtLeastScalar(u8, input_line, 1, c);
//                     if (token.negative and !contains_char) {
//                         break true;
//                     }
//                     if (!token.negative and contains_char) {
//                         break true;
//                     }
//                 } else false;
//                 if (result) {
//                     token_index += 1;
//                     continue;
//                 }
//                 if (token_index == 0 and token_index != tokens.items.len - 1) {
//                     continue;
//                 }
//                 break false;
//             },
//             else => break false,
//         }
//         if (token.is_end_with and char_index != input_line.len - 1) {
//             break false;
//         }
//     } else true;
//     return matched;
// }

pub fn main() !void {
    // var buffer: [1024]u8 = undefined;
    // var fba = std.heap.FixedBufferAllocator.init(&buffer);
    // const allocator = fba.allocator();
    //
    // const args = try std.process.argsAlloc(allocator);
    // defer std.process.argsFree(allocator, args);
    //
    // if (args.len < 3 or !std.mem.eql(u8, args[1], "-E")) {
    //     std.debug.print("Expected first argument to be '-E'\n", .{});
    //     std.process.exit(1);
    // }
    //
    // std.debug.print("Logs from your program will appear here!\n", .{});
    //
    // const pattern = args[2];
    // var input_line: [1024]u8 = undefined;
    // const input_len = try std.io.getStdIn().reader().read(&input_line);
    // const input_slice = input_line[0..input_len];
    // if (try matchPattern(input_slice, pattern)) {
    //     std.debug.print("matched", .{});
    //     std.process.exit(0);
    // } else {
    //     std.debug.print("not matched", .{});
    //     std.process.exit(1);
    // }
}
