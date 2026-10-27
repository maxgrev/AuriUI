//
//  AuriUILexer.swift
//  AuriUI
//
//  Tokenizes one AuriUI line into keyword, positionals, key:value pairs, and
//  a trailing action. The lexer knows nothing about section semantics; it only
//  enforces the lexical rules in GRAMMAR.md.
//

import Foundation

struct AuriUILexedLine {
    var keyword: String
    /// The first bare token that reads as emoji art (the visual slot).
    var emoji: String?
    /// Positional quoted strings, in order.
    var strings: [String]
    /// Bare tokens that are neither the keyword nor emoji (`check`, `multi`,
    /// `primary`, `sel`, a screen id, …), in order.
    var flags: [String]
    /// `key:value` pairs in order; keys may repeat (`s:` on cards).
    var pairs: [Pair]
    var action: AuriUIAction?

    struct Pair {
        var key: String
        var value: String
    }

    func pair(_ key: String) -> String? {
        pairs.first(where: { $0.key == key })?.value
    }

    func pairValues(_ key: String) -> [String] {
        pairs.filter { $0.key == key }.map(\.value)
    }

    func hasFlag(_ flag: String) -> Bool {
        flags.contains(flag)
    }
}

enum AuriUILexResult {
    /// Blank line or `#` comment — skipped without being counted as dropped.
    case ignored
    /// Lexically broken (unterminated quote, malformed action) — dropped.
    case malformed
    case line(AuriUILexedLine)
}

enum AuriUILexer {

    static func tokenize(_ raw: String) -> AuriUILexResult {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else {
            return .ignored
        }

        let chars = Array(trimmed)
        var index = 0

        var keyword: String?
        var emoji: String?
        var strings: [String] = []
        var flags: [String] = []
        var pairs: [AuriUILexedLine.Pair] = []
        var action: AuriUIAction?

        func skipWhitespace() {
            while index < chars.count, chars[index].isWhitespace {
                index += 1
            }
        }

        /// Reads a `"…"` string starting at the opening quote. Returns nil on
        /// an unterminated quote, which invalidates the whole line.
        func readQuoted() -> String? {
            index += 1
            var out = ""
            while index < chars.count {
                let character = chars[index]
                if character == "\\", index + 1 < chars.count,
                   chars[index + 1] == "\"" || chars[index + 1] == "\\" {
                    out.append(chars[index + 1])
                    index += 2
                    continue
                }
                if character == "\"" {
                    index += 1
                    return out
                }
                out.append(character)
                index += 1
            }
            return nil
        }

        outer: while index < chars.count {
            skipWhitespace()
            guard index < chars.count else { break }

            if chars[index] == "\"" {
                guard let value = readQuoted() else { return .malformed }
                strings.append(value)
                continue
            }

            if chars[index] == "@" {
                index += 1
                var kind = ""
                while index < chars.count, chars[index].isLetter {
                    kind.append(chars[index])
                    index += 1
                }
                guard index < chars.count, chars[index] == "(" else { return .malformed }
                index += 1
                skipWhitespace()

                let argument: String
                if index < chars.count, chars[index] == "\"" {
                    guard let value = readQuoted() else { return .malformed }
                    argument = value
                    skipWhitespace()
                    guard index < chars.count, chars[index] == ")" else { return .malformed }
                    index += 1
                } else {
                    var depth = 1
                    var out = ""
                    while index < chars.count {
                        let character = chars[index]
                        if character == "(" { depth += 1 }
                        if character == ")" {
                            depth -= 1
                            if depth == 0 {
                                index += 1
                                break
                            }
                        }
                        out.append(character)
                        index += 1
                    }
                    guard depth == 0 else { return .malformed }
                    argument = out.trimmingCharacters(in: .whitespaces)
                }

                // Unknown action kinds degrade to no action (forward compat);
                // the line itself survives.
                action = Self.action(kind: kind, argument: argument)
                continue
            }

            var word = ""
            while index < chars.count, !chars[index].isWhitespace, chars[index] != "\"" {
                if chars[index] == ":", !word.isEmpty, keyword != nil {
                    index += 1
                    let value: String
                    if index < chars.count, chars[index] == "\"" {
                        guard let quoted = readQuoted() else { return .malformed }
                        value = quoted
                    } else {
                        var bare = ""
                        while index < chars.count, !chars[index].isWhitespace {
                            bare.append(chars[index])
                            index += 1
                        }
                        value = bare
                    }
                    pairs.append(.init(key: word, value: value))
                    continue outer
                }
                word.append(chars[index])
                index += 1
            }

            guard !word.isEmpty else { continue }
            if keyword == nil {
                keyword = word.lowercased()
            } else if emoji == nil, Self.isEmojiToken(word) {
                emoji = word
            } else {
                flags.append(word)
            }
        }

        guard let keyword else { return .malformed }
        return .line(AuriUILexedLine(
            keyword: keyword,
            emoji: emoji,
            strings: strings,
            flags: flags,
            pairs: pairs,
            action: action
        ))
    }

    private static func action(kind: String, argument: String) -> AuriUIAction? {
        switch kind.lowercased() {
        case "send":
            return argument.isEmpty ? nil : .send(prompt: argument)
        case "nav":
            return argument.isEmpty ? nil : .nav(brief: argument)
        case "url":
            return urlTarget(argument).map { .url($0) }
        default:
            return nil
        }
    }

    /// `r3` → resource, `find:"…"`/`find:…` → lookup, `https://…` → direct.
    static func urlTarget(_ argument: String) -> AuriUIURLTarget? {
        let trimmed = argument.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        if isResourceID(trimmed) {
            return .resource(id: trimmed.lowercased())
        }
        if trimmed.lowercased().hasPrefix("find:") {
            var query = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            if query.hasPrefix("\""), query.hasSuffix("\""), query.count >= 2 {
                query = String(query.dropFirst().dropLast())
            }
            return query.isEmpty ? nil : .lookup(query: query)
        }
        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
           scheme == "https" || scheme == "http" {
            return .direct(url)
        }
        return nil
    }

    /// `r` followed by digits (r1, r12, …).
    static func isResourceID(_ value: String) -> Bool {
        guard value.count >= 2, value.lowercased().hasPrefix("r") else { return false }
        return value.dropFirst().allSatisfy(\.isNumber)
    }

    /// True when a bare token is emoji art rather than a flag. Digits report
    /// `isEmoji` but must stay bare tokens, hence the pictograph plane check.
    static func isEmojiToken(_ token: String) -> Bool {
        guard let scalar = token.unicodeScalars.first else { return false }
        if scalar.properties.isEmojiPresentation { return true }
        if scalar.properties.isEmoji, scalar.value >= 0x1F000 { return true }
        return token.unicodeScalars.contains { $0.value == 0xFE0F }
    }
}

public extension AuriUIURLTarget {
    /// Parses a reference string exactly as the grammar writes it in `url:`
    /// key positions: `r3`, `find:"query"`, or a literal http(s) URL.
    init?(parsing raw: String) {
        guard let target = AuriUILexer.urlTarget(raw) else {
            return nil
        }
        self = target
    }
}
