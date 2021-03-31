const Tokenizer = @This();

const std = @import("std");
const log = std.log.scoped(.tokenizer);
const testing = std.testing;

buffer: []const u8,
index: usize = 0,

pub const Token = struct {
    id: Id,
    start: usize,
    end: usize,

    pub const Id = enum {
        Eof,

        NewLine,
        DocStart, // ---
        DocEnd, // ...
        SeqItemInd, // -
        MapValueInd, // :
        FlowMapStart, // {
        FlowMapEnd, // }
        FlowSeqStart, // [
        FlowSeqEnd, // ]

        Comma,
        Space,
        Comment, // #
        Alias, // *
        Anchor, // &
        Tag, // !
        SingleQuote, // '
        DoubleQuote, // "

        Literal,
    };
};

pub const TokenIndex = usize;

pub const TokenIterator = struct {
    buffer: []const Token,
    pos: TokenIndex = 0,

    pub fn next(self: *TokenIterator) Token {
        const token = self.buffer[self.pos];
        self.pos += 1;
        return token;
    }

    pub fn peek(self: TokenIterator) ?Token {
        if (self.pos >= self.buffer.len) return null;
        return self.buffer[self.pos];
    }

    pub fn resetTo(self: *TokenIterator, pos: TokenIndex) void {
        self.pos = pos;
    }

    pub fn advanceBy(self: *TokenIterator, offset: TokenIndex) void {
        if (offset == 0) return;
        self.pos += offset - 1;
    }

    pub fn getPos(self: TokenIterator) TokenIndex {
        if (self.pos == 0) return 0;
        return self.pos - 1;
    }
};

pub fn next(self: *Tokenizer) Token {
    var result = Token{
        .id = .Eof,
        .start = self.index,
        .end = undefined,
    };

    var state: union(enum) {
        Start,
        Space,
        NewLine,
        Hyphen: usize,
        Dot: usize,
        Literal,
    } = .Start;

    while (self.index < self.buffer.len) : (self.index += 1) {
        const c = self.buffer[self.index];
        switch (state) {
            .Start => switch (c) {
                ' ', '\t' => {
                    state = .Space;
                },
                '\n' => {
                    result.id = .NewLine;
                    self.index += 1;
                    break;
                },
                '\r' => {
                    state = .NewLine;
                },
                '-' => {
                    state = .{ .Hyphen = 1 };
                },
                '.' => {
                    state = .{ .Dot = 1 };
                },
                ',' => {
                    result.id = .Comma;
                    self.index += 1;
                    break;
                },
                '#' => {
                    result.id = .Comment;
                    self.index += 1;
                    break;
                },
                '*' => {
                    result.id = .Alias;
                    self.index += 1;
                    break;
                },
                '&' => {
                    result.id = .Anchor;
                    self.index += 1;
                    break;
                },
                '!' => {
                    result.id = .Tag;
                    self.index += 1;
                    break;
                },
                '\'' => {
                    result.id = .SingleQuote;
                    self.index += 1;
                    break;
                },
                '"' => {
                    result.id = .DoubleQuote;
                    self.index += 1;
                    break;
                },
                '[' => {
                    result.id = .FlowSeqStart;
                    self.index += 1;
                    break;
                },
                ']' => {
                    result.id = .FlowSeqEnd;
                    self.index += 1;
                    break;
                },
                ':' => {
                    result.id = .MapValueInd;
                    self.index += 1;
                    break;
                },
                '{' => {
                    result.id = .FlowMapStart;
                    self.index += 1;
                    break;
                },
                '}' => {
                    result.id = .FlowMapEnd;
                    self.index += 1;
                    break;
                },
                else => {
                    state = .Literal;
                },
            },
            .NewLine => switch (c) {
                '\n' => {
                    result.id = .NewLine;
                    self.index += 1;
                    break;
                },
                else => {}, // TODO this should be an error condition
            },
            .Space => switch (c) {
                ' ', '\t' => {},
                else => {
                    result.id = .Space;
                    break;
                },
            },
            .Hyphen => |*count| switch (c) {
                ' ' => {
                    result.id = .SeqItemInd;
                    self.index += 1;
                    break;
                },
                '-' => {
                    count.* += 1;

                    if (count.* == 3) {
                        result.id = .DocStart;
                        self.index += 1;
                        break;
                    }
                },
                else => {
                    state = .Literal;
                },
            },
            .Dot => |*count| switch (c) {
                '.' => {
                    count.* += 1;

                    if (count.* == 3) {
                        result.id = .DocEnd;
                        self.index += 1;
                        break;
                    }
                },
                else => {
                    state = .Literal;
                },
            },
            .Literal => switch (c) {
                '\r', '\n', ' ', '\'', '"', ',', ':', ']', '}' => {
                    result.id = .Literal;
                    break;
                },
                else => {
                    result.id = .Literal;
                },
            },
        }
    }

    result.end = self.index;

    log.debug("{any}", .{result});
    log.debug("    | {s}", .{self.buffer[result.start..result.end]});

    return result;
}

fn testExpected(source: []const u8, expected: []const Token.Id) void {
    var tokenizer = Tokenizer{
        .buffer = source,
    };

    for (expected) |exp| {
        const token = tokenizer.next();
        testing.expectEqual(exp, token.id);
    }
}

test "empty doc" {
    testExpected("", &[_]Token.Id{.Eof});
}

test "empty doc with explicit markers" {
    testExpected(
        \\---
        \\...
    , &[_]Token.Id{
        .DocStart, .NewLine, .DocEnd, .Eof,
    });
}

test "sequence of values" {
    testExpected(
        \\- val1
        \\- val2
    , &[_]Token.Id{
        .SeqItemInd,
        .Literal,
        .NewLine,
        .SeqItemInd,
        .Literal,
        .Eof,
    });
}

test "sequence of sequences" {
    testExpected(
        \\- [ val1, val2]
        \\- [val3, val4 ]
    , &[_]Token.Id{
        .SeqItemInd,
        .FlowSeqStart,
        .Space,
        .Literal,
        .Comma,
        .Space,
        .Literal,
        .FlowSeqEnd,
        .NewLine,
        .SeqItemInd,
        .FlowSeqStart,
        .Literal,
        .Comma,
        .Space,
        .Literal,
        .Space,
        .FlowSeqEnd,
        .Eof,
    });
}

test "mappings" {
    testExpected(
        \\key1: value1
        \\key2: value2
    , &[_]Token.Id{
        .Literal,
        .MapValueInd,
        .Space,
        .Literal,
        .NewLine,
        .Literal,
        .MapValueInd,
        .Space,
        .Literal,
        .Eof,
    });
}

test "inline mapped sequence of values" {
    testExpected(
        \\key :  [ val1, 
        \\          val2 ]
    , &[_]Token.Id{
        .Literal,
        .Space,
        .MapValueInd,
        .Space,
        .FlowSeqStart,
        .Space,
        .Literal,
        .Comma,
        .Space,
        .NewLine,
        .Space,
        .Literal,
        .Space,
        .FlowSeqEnd,
        .Eof,
    });
}

test "part of tdb" {
    testExpected(
        \\--- !tapi-tbd
        \\tbd-version:     4
        \\targets:         [ x86_64-macos ]
        \\
        \\uuids:
        \\  - target:          x86_64-macos
        \\    value:           F86CC732-D5E4-30B5-AA7D-167DF5EC2708
        \\
        \\install-name:    '/usr/lib/libSystem.B.dylib'
        \\...
    , &[_]Token.Id{
        .DocStart,
        .Space,
        .Tag,
        .Literal,
        .NewLine,
        .Literal,
        .MapValueInd,
        .Space,
        .Literal,
        .NewLine,
        .Literal,
        .MapValueInd,
        .Space,
        .FlowSeqStart,
        .Space,
        .Literal,
        .Space,
        .FlowSeqEnd,
        .NewLine,
        .NewLine,
        .Literal,
        .MapValueInd,
        .NewLine,
        .Space,
        .SeqItemInd,
        .Literal,
        .MapValueInd,
        .Space,
        .Literal,
        .NewLine,
        .Space,
        .Literal,
        .MapValueInd,
        .Space,
        .Literal,
        .NewLine,
        .NewLine,
        .Literal,
        .MapValueInd,
        .Space,
        .SingleQuote,
        .Literal,
        .SingleQuote,
        .NewLine,
        .DocEnd,
        .Eof,
    });
}
