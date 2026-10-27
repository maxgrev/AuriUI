//
//  LexerTests.swift
//  AuriUITests
//

import Foundation
import Testing
@testable import AuriUI

@Suite("Lexer")
struct LexerTests {

    @Test("A full item line tokenizes into every slot")
    func fullItemLine() throws {
        let result = AuriUILexer.tokenize(
            #"item 🥓 "Applewood bacon" "Crispy and smoked" val:bacon price:2.00 sel @send("Add bacon")"#
        )
        guard case .line(let line) = result else {
            Issue.record("Expected a lexed line")
            return
        }

        #expect(line.keyword == "item")
        #expect(line.emoji == "🥓")
        #expect(line.strings == ["Applewood bacon", "Crispy and smoked"])
        #expect(line.pair("val") == "bacon")
        #expect(line.pair("price") == "2.00")
        #expect(line.hasFlag("sel"))
        #expect(line.action == .send(prompt: "Add bacon"))
    }

    @Test("Escaped quotes and backslashes survive")
    func escapes() throws {
        guard case .line(let line) = AuriUILexer.tokenize(#"intro "She said \"hi\" and left a \\ behind""#) else {
            Issue.record("Expected a lexed line")
            return
        }
        #expect(line.strings == [#"She said "hi" and left a \ behind"#])
    }

    @Test("Repeated s: pairs are all preserved, in order")
    func repeatedPairs() throws {
        guard case .line(let line) = AuriUILexer.tokenize(#"item "Tesla" s:"Range=333 mi" s:"0-60=4.2 s""#) else {
            Issue.record("Expected a lexed line")
            return
        }
        #expect(line.pairValues("s") == ["Range=333 mi", "0-60=4.2 s"])
    }

    @Test("Bare @url arguments parse without quotes")
    func bareURLAction() throws {
        guard case .line(let line) = AuriUILexer.tokenize(#"button "Book now" @url(https://example.com/a?b=1)"#) else {
            Issue.record("Expected a lexed line")
            return
        }
        #expect(line.action == .url(.direct(URL(string: "https://example.com/a?b=1")!)))
    }

    @Test(
        "URL targets: resource ids, tap-time lookups, literals",
        arguments: [
            ("r3", AuriUIURLTarget.resource(id: "r3")),
            ("R12", .resource(id: "r12")),
            ("find:\"dune part two official trailer\"", .lookup(query: "dune part two official trailer")),
            ("find:trailers", .lookup(query: "trailers")),
            ("https://example.com", .direct(URL(string: "https://example.com")!)),
        ] as [(String, AuriUIURLTarget)]
    )
    func urlTargets(argument: String, expected: AuriUIURLTarget) {
        #expect(AuriUILexer.urlTarget(argument) == expected)
    }

    @Test("Non-URL @url arguments drop the action, not the line")
    func invalidURLTargets() throws {
        #expect(AuriUILexer.urlTarget("recipes") == nil, "A bare word is not a reference")
        #expect(AuriUILexer.urlTarget("javascript:alert(1)") == nil)
        guard case .line(let line) = AuriUILexer.tokenize(#"button "Order" @url(not a url)"#) else {
            Issue.record("Expected a lexed line")
            return
        }
        #expect(line.action == nil)
    }

    @Test("Host capabilities cannot be authored through the wire format")
    func hostCapabilityIsInMemoryOnly() {
        guard case .line(let line) = AuriUILexer.tokenize(
            #"button "Connect" @hostCapability(integration.connect)"#
        ) else {
            Issue.record("Expected a lexed line")
            return
        }

        #expect(line.action == nil)
        let action = AuriUIAction.hostCapability(
            id: "host.integration.connect"
        )
        #expect(action.capabilityID == "host.integration.connect")
    }

    @Test("Host-authored buttons can expose loading state")
    func hostButtonState() {
        #expect(AuriUIButton(label: "Connect").state == .enabled)
        #expect(
            AuriUIButton(
                label: "Connecting…",
                action: .hostCapability(id: "host.integration.connect"),
                state: .loading
            ).state == .loading
        )
    }

    @Test("Unterminated quotes invalidate the whole line")
    func unterminatedQuote() {
        guard case .malformed = AuriUILexer.tokenize(#"item "Butter" "1 cup"#) else {
            Issue.record("Expected malformed")
            return
        }
    }

    @Test("Blank lines and comments are ignored")
    func ignoredLines() {
        guard case .ignored = AuriUILexer.tokenize("   ") else {
            Issue.record("Expected ignored")
            return
        }
        guard case .ignored = AuriUILexer.tokenize("# note to self") else {
            Issue.record("Expected ignored")
            return
        }
    }

    @Test(
        "Emoji tokens are recognized; flags and numbers are not",
        arguments: [
            ("🥓", true), ("🌶", true), ("🧀", true), ("⭐", true), ("❤️", true),
            ("check", false), ("sel", false), ("2.50", false), ("M4", false), ("brioche", false),
        ] as [(String, Bool)]
    )
    func emojiDetection(token: String, isEmoji: Bool) {
        #expect(AuriUILexer.isEmojiToken(token) == isEmoji)
    }
}
