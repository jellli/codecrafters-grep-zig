const std = @import("std");
const testing = std.testing;

fn isDigit(char: u8) bool {
    return char >= '0' and char <= '9';
}

const Pattern = union(enum) { Digit, Char: u8, AlphaNumeric, PositiveCharGroup: []const u8, NegativeCharGroup: []const u8, StartAnchor, EndAnchor, OneOrMore, ZeroOrOne, Any };
const TokenizeError = error{
    InvalidPattern,
};

fn prevChar(text: []const u8, current_index: *usize) ?u8 {
    if (current_index.* - 1 < text.len) {
        current_index.* -= 1;
        return text[current_index.*];
    } else {
        return null;
    }
}
fn nextChar(text: []const u8, current_index: *usize) ?u8 {
    if (current_index.* + 1 < text.len) {
        current_index.* += 1;
        return text[current_index.*];
    } else {
        return null;
    }
}

fn prevToken(tokens: []Pattern, current_index: *usize) ?Pattern {
    if (current_index.* - 1 < tokens.len) {
        current_index.* -= 1;
        return tokens[current_index.*];
    } else {
        return null;
    }
}
fn nextToken(tokens: []Pattern, current_index: *usize) ?Pattern {
    if (current_index.* + 1 < tokens.len) {
        current_index.* += 1;
        return tokens[current_index.*];
    } else {
        return null;
    }
}

fn tokenize(allocator: std.mem.Allocator, pattern: []const u8) !std.ArrayList(Pattern) {
    var patterns = std.ArrayList(Pattern).init(allocator);
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
                    'd' => try patterns.append(.Digit),
                    'w' => try patterns.append(.AlphaNumeric),
                    else => return TokenizeError.InvalidPattern,
                } else return TokenizeError.InvalidPattern;
            },
            '[' => {
                if (nextChar(pattern, &pattern_index)) |next_char| {
                    var negative_flag = false;
                    if (next_char == '^') {
                        negative_flag = true;
                        _ = nextChar(pattern, &pattern_index) orelse return TokenizeError.InvalidPattern;
                    }

                    const closed_pos = std.mem.indexOfScalar(u8, pattern[pattern_index..], ']') orelse return TokenizeError.InvalidPattern;
                    const char_slice = pattern[pattern_index .. pattern_index + closed_pos];
                    if (char_slice.len == 0) return TokenizeError.InvalidPattern;
                    try patterns.append(if (negative_flag) .{ .NegativeCharGroup = char_slice } else .{ .PositiveCharGroup = char_slice });
                    pattern_index += char_slice.len + 1;
                } else return TokenizeError.InvalidPattern;
            },
            '^' => {
                if (has_start_anchor) {
                    return TokenizeError.InvalidPattern;
                }
                has_start_anchor = true;
                try patterns.append(.StartAnchor);
            },
            '$' => {
                if (pattern_index != pattern.len - 1) {
                    return TokenizeError.InvalidPattern;
                }
                try patterns.append(.EndAnchor);
            },
            '+' => {
                if (patterns.getLastOrNull()) |prev_token| {
                    switch (prev_token) {
                        .OneOrMore, .ZeroOrOne, .StartAnchor, .EndAnchor => return TokenizeError.InvalidPattern,
                        else => {
                            try patterns.insert(patterns.items.len - 1, .OneOrMore);
                        },
                    }
                } else {
                    return TokenizeError.InvalidPattern;
                }
            },
            '?' => {
                if (patterns.getLastOrNull()) |prev_token| {
                    switch (prev_token) {
                        .OneOrMore, .ZeroOrOne, .StartAnchor, .EndAnchor => return TokenizeError.InvalidPattern,
                        else => {
                            try patterns.insert(patterns.items.len - 1, .ZeroOrOne);
                        },
                    }
                } else {
                    return TokenizeError.InvalidPattern;
                }
            },
            '.' => try patterns.append(.Any),
            else => {
                try patterns.append(.{ .Char = char });
            },
        }
    }
    // std.debug.print("{any}\n", .{patterns.items});
    return patterns;
}

const MatchConfig = struct {
    text: []const u8,
    start_text_index: ?usize = 0,
    start_token_index: ?usize = 0,
};

const Regex = struct {
    allocator: std.mem.Allocator,
    pattern: []const u8,
    patterns: std.ArrayList(Pattern),

    const Self = @This();

    fn init(
        allocator: std.mem.Allocator,
        pattern: []const u8,
    ) !@This() {
        return .{
            .allocator = allocator,
            .pattern = pattern,
            .patterns = try tokenize(allocator, pattern),
        };
    }

    fn matchToken(char: u8, token: Pattern, text: []const u8, text_index: *usize) !bool {
        switch (token) {
            .Any => {
                text_index.* += 1;
                return true;
            },
            .Char => |c| {
                if (char == c) {
                    text_index.* += 1;
                    return true;
                }
                return false;
            },
            .Digit => {
                if (isDigit(char)) {
                    text_index.* += 1;
                    return true;
                }
                return false;
            },
            .AlphaNumeric => {
                if (std.ascii.isAlphanumeric(char) or char == '_') {
                    text_index.* += 1;
                    return true;
                }
                return false;
            },
            .PositiveCharGroup => |str| {
                for (text) |c| {
                    if (std.mem.indexOfScalar(u8, str, c) != null) {
                        text_index.* += 1;
                        return true;
                    }
                }
                return false;
            },
            .NegativeCharGroup => |str| {
                for (text) |c| {
                    if (std.mem.indexOfScalar(u8, str, c) == null) {
                        text_index.* += 1;
                        return true;
                    }
                }
                return false;
            },
            else => return false,
        }
    }

    fn match(self: *const Self, config: MatchConfig) bool {
        const text = config.text;
        var text_index: usize = config.start_text_index orelse 0;
        var token_index: usize = config.start_token_index orelse 0;
        const tokens = self.patterns.items;

        loop: while (token_index < tokens.len) {
            const should_continue = token_index == 0 and token_index != tokens.len - 1;
            const current_token = tokens[token_index];
            // std.debug.print("{any},{d}\t{s},{d}\n", .{ current_token, token_index, text, text_index });
            switch (current_token) {
                .StartAnchor => {
                    if (text_index != 0) {
                        return false;
                    }
                    token_index += 1;
                    continue;
                },
                .EndAnchor => {
                    if (text_index != text.len) {
                        return false;
                    }
                    token_index += 1;
                    continue;
                },
                else => {
                    if (text_index >= text.len) return false;
                    const char = text[text_index];
                    switch (current_token) {
                        .Any, .Char, .Digit, .AlphaNumeric, .PositiveCharGroup, .NegativeCharGroup => {
                            if (!try matchToken(
                                char,
                                current_token,
                                text[text_index..],
                                &text_index,
                            )) {
                                if (should_continue) {
                                    text_index += 1;
                                    continue;
                                } else {
                                    return false;
                                }
                            }
                            token_index += 1;
                            continue;
                        },
                        .OneOrMore => {
                            if (nextToken(tokens, &token_index)) |next_token| {
                                var matched_chars: usize = 0;
                                var temp_text_index = text_index;

                                // Greedily match as many as possible
                                while (temp_text_index < text.len) {
                                    if (!try matchToken(text[temp_text_index], next_token, text[temp_text_index..], &temp_text_index)) {
                                        break;
                                    }
                                    matched_chars += 1;
                                }

                                // Try to backtrack if needed
                                while (matched_chars > 0) {
                                    const saved_text_index = text_index + matched_chars;
                                    const saved_token_index = token_index + 1;

                                    if (self.match(.{
                                        .text = text,
                                        .start_text_index = saved_text_index,
                                        .start_token_index = saved_token_index,
                                    })) {
                                        text_index = saved_text_index;
                                        token_index = saved_token_index;
                                        continue :loop;
                                    }

                                    matched_chars -= 1;
                                }

                                if (matched_chars == 0) {
                                    return false;
                                }
                            }
                        },
                        .ZeroOrOne => {
                            if (nextToken(tokens, &token_index)) |next_token| {
                                var matched_chars: isize = 0;
                                var temp_text_index = text_index;

                                while (matched_chars < 1) {
                                    if (!try matchToken(text[temp_text_index], next_token, text[temp_text_index..], &temp_text_index)) {
                                        break;
                                    }
                                    matched_chars += 1;
                                }

                                while (matched_chars >= 0) : (matched_chars -= 1) {
                                    const i: usize = @intCast(matched_chars);
                                    const saved_text_index = text_index + i;
                                    const saved_token_index = token_index + 1;

                                    if (self.match(.{
                                        .text = text,
                                        .start_text_index = saved_text_index,
                                        .start_token_index = saved_token_index,
                                    })) {
                                        text_index = saved_text_index;
                                        token_index = saved_token_index;
                                        continue :loop;
                                    }
                                }
                            }
                        },
                        else => return false,
                    }
                },
            }
        }
        return true;
    }
};

test "regex plain string one or more tokenize and match" {
    const allocator = std.heap.page_allocator;
    const pattern = "ca+at";
    const reg = try Regex.init(allocator, pattern);

    try testing.expect(reg.match(.{ .text = "caaat" }) == true); // Should match "ca" + "aa" + "at"
    try testing.expect(reg.match(.{ .text = "caat" }) == true); // Should match "ca" + "a" + "at"
    try testing.expect(reg.match(.{ .text = "cat" }) == false); // Missing 'a' before 't'
    try testing.expect(reg.match(.{ .text = "caaa" }) == false); // Missing 't'
}

test "regex plain string zero or one tokenize and match" {
    const allocator = std.heap.page_allocator;
    const pattern = "ca?at";
    const reg = try Regex.init(allocator, pattern);

    try testing.expect(reg.match(.{ .text = "caaat" }) == false);
    try testing.expect(reg.match(.{ .text = "caat" }) == true);
    try testing.expect(reg.match(.{ .text = "cat" }) == true);
    try testing.expect(reg.match(.{ .text = "caaa" }) == false);
}

test "regex plain string tokenize and match" {
    const allocator = std.heap.page_allocator;
    const pattern = "dog";
    const short_pattern = "d";
    const reg = try Regex.init(allocator, pattern);
    const short_reg = try Regex.init(allocator, short_pattern);

    try testing.expect(short_reg.match(.{ .text = "d" }) == true);
    try testing.expect(short_reg.match(.{ .text = "o" }) == false);

    for (reg.patterns.items, "dog") |token, char| {
        try testing.expectEqual(Pattern{ .Char = char }, token);
    }
    try testing.expect(reg.match(.{ .text = "dog" }) == true);
    try testing.expect(reg.match(.{ .text = "dogs" }) == true);
    try testing.expect(reg.match(.{ .text = "pog" }) == false);
    try testing.expect(reg.match(.{ .text = "dig" }) == false);
    try testing.expect(reg.match(.{ .text = "dok" }) == false);
}

test "regex digit tokenize and match" {
    const allocator = std.heap.page_allocator;
    const pattern = "\\d\\d";
    const reg = try Regex.init(allocator, pattern);
    try testing.expect(reg.patterns.items.len == 2);
    try testing.expectEqual(reg.patterns.items[0], Pattern{ .Digit = {} });
    try testing.expectEqual(reg.patterns.items[1], Pattern{ .Digit = {} });

    try testing.expect(reg.match(.{ .text = "10" }) == true);
    try testing.expect(reg.match(.{ .text = "90" }) == true);
    try testing.expect(reg.match(.{ .text = "r3" }) == false);
    try testing.expect(reg.match(.{ .text = "3r" }) == false);
    try testing.expect(reg.match(.{ .text = "rr" }) == false);
}

test "regex alphaNumeric tokenize and match" {
    const allocator = std.heap.page_allocator;
    const pattern = "\\w\\w";
    const reg = try Regex.init(allocator, pattern);
    try testing.expect(reg.patterns.items.len == 2);
    try testing.expectEqual(reg.patterns.items[0], Pattern{ .AlphaNumeric = {} });
    try testing.expectEqual(reg.patterns.items[1], Pattern{ .AlphaNumeric = {} });

    try testing.expect(reg.match(.{ .text = "10" }) == true);
    try testing.expect(reg.match(.{ .text = "90" }) == true);
    try testing.expect(reg.match(.{ .text = "r_" }) == true);
}

test "regex positive/negative char group tokenize" {
    const allocator = std.heap.page_allocator;
    const n_pattern = "[^opq]";
    const p_pattern = "[abc]";
    const n_reg = try Regex.init(allocator, n_pattern);
    const p_reg = try Regex.init(allocator, p_pattern);
    try testing.expect(n_reg.patterns.items.len == 1);
    try testing.expect(p_reg.patterns.items.len == 1);
    try testing.expectEqualStrings("opq", n_reg.patterns.items[0].NegativeCharGroup);
    try testing.expectEqualStrings("abc", p_reg.patterns.items[0].PositiveCharGroup);

    try testing.expect(n_reg.match(.{ .text = "orange" }) == true);
    try testing.expect(n_reg.match(.{ .text = "banana" }) == true);
    try testing.expect(n_reg.match(.{ .text = "oops" }) == true);
    try testing.expect(n_reg.match(.{ .text = "oop" }) == false);

    try testing.expect(p_reg.match(.{ .text = "banana" }) == true);
    try testing.expect(p_reg.match(.{ .text = "bob" }) == true);
    try testing.expect(p_reg.match(.{ .text = "dog" }) == false);
}

test "regex start/end anchor tokenize" {
    const allocator = std.heap.page_allocator;
    const s_pattern = "^log";
    const e_pattern = "big$";
    const s_reg = try Regex.init(allocator, s_pattern);
    const e_reg = try Regex.init(allocator, e_pattern);
    try testing.expect(s_reg.patterns.items.len == 4);
    try testing.expect(e_reg.patterns.items.len == 4);

    try testing.expect(s_reg.match(.{ .text = "log" }) == true);
    try testing.expect(s_reg.match(.{ .text = "logs" }) == true);
    try testing.expect(s_reg.match(.{ .text = "alog" }) == false);

    try testing.expect(e_reg.match(.{ .text = "big" }) == true);
    try testing.expect(e_reg.match(.{ .text = "abig" }) == true);
    try testing.expect(e_reg.match(.{ .text = "bigy" }) == false);
}

fn matchPattern(input_line: []const u8, pattern: []const u8) !bool {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const reg = try Regex.init(allocator, pattern);
    return reg.match(.{
        .text = input_line,
    });
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
