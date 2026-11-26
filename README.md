# AuriUI

[![CI](https://github.com/maxgrev/AuriUI/actions/workflows/ci.yml/badge.svg)](https://github.com/maxgrev/AuriUI/actions/workflows/ci.yml)
![Swift 6](https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white)
![Platforms](https://img.shields.io/badge/Platforms-iOS%2016%2B%20%7C%20macOS%2013%2B%20%7C%20watchOS%209%2B-000000?logo=apple&logoColor=white)
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache--2.0-blue.svg)](LICENSE)

**A native Swift 6 and SwiftUI generative UI framework for streaming interactive screens from LLMs.**

AuriUI parses a compact, line-oriented text grammar instead of nested JSON component trees. Each completed line renders into native SwiftUI views the moment its newline arrives, keeps selections, forms, and `Decimal` pricing state on device, and returns typed actions to your app.

```text
aui 1
screen lunch "Choose lunch"
state base:10.00 cur:USD
list "Extras" multi
item 🧀 "Cheese" val:cheese price:1.25
item 🥓 "Bacon" val:bacon price:2.00
button primary "Order · {total}" @send("Order with {selections} for {total}")
```

Seven lines produce a titled native screen with multi-select options, client-computed `Decimal` totals (`{total}`), and an interpolated host action (`{selections}`).

This repository includes the Foundation-only streaming parser (`AuriUI`), SwiftUI renderer and SSE HTTP client (`AuriUIRenderer`), a single cross-language contract (`Contract/auriui-v1.json`) generating Swift and JavaScript, a standalone iOS demo app (`Examples/AuriUIDemo`), and a deployable [Cloudflare Worker + Cerebras reference backend](Backend/README.md).

## Why a line-oriented grammar

Most generative UI protocols (including JSON message streams like Google's A2UI) express UI as nested JSON objects built around cross-platform schemas. AuriUI makes a different tradeoff for native Apple apps:

- **Paint on every newline:** one line equals one renderable node. The client renders each section as soon as `\n` arrives, without waiting for closing braces or running speculative partial-JSON repair.
- **Small token budget:** flat positional syntax drops repeated field keys, braces, wrapper arrays, and schema boilerplate. Screens target ~300 tokens (fixture tests enforce a 500-token ceiling), cutting generation time and token cost.
- **Native Apple stack end to end:** the core package (`AuriUI`) depends only on `Foundation` and compiles on iOS 16+, macOS 13+, and watchOS 9+. The renderer (`AuriUIRenderer`) builds directly on SwiftUI, Apple Charts, and Observation with no WebView or JavaScript bridge.
- **Single source of truth across client and server:** `Contract/auriui-v1.json` generates both the Swift contract and the backend JavaScript prompt/validator contract (`Contract/auriui-v1.generated.mjs`), checked by parity tests in CI.

## Design invariants

LLMs make mistakes. AuriUI's [grammar specification](GRAMMAR.md) enforces six rules so partial or imperfect model output degrades safely:

1. **One line = one renderable node.** A line parses the moment its newline arrives. No construct spans lines except containers collecting subsequent `item` lines.
2. **Lossy by line.** A malformed line drops individually while the rest of the document survives. Empty containers drop cleanly; a document with zero valid sections fails cleanly so your app can fall back.
3. **The model never does math.** Items carry `price:` values; the client computes every `Decimal` total (`{total}`) and receipt sum locally.
4. **Capability-gated forms.** A form targets one registered host capability, validates locally, asks for confirmation, and submits through a matching action. AuriUI v1 has no password, payment, booking, health, or other sensitive field types.
5. **Grounded charts.** Every chart requires one explicit unit, bounded points (2 to 12), and complete values across every X/series pair. The client computes scales and never fabricates missing points.
6. **Forward compatible.** Unknown `key:value` pairs are ignored and unknown keywords drop only that line. The `aui <version>` header gates breaking changes.

## Package products & components

| Product | Purpose | Requirements |
| --- | --- | --- |
| `AuriUI` | Documents, lexer, streaming parser, forms, selections, `Decimal` pricing, snapshots | Swift 6; iOS 16+, macOS 13+, watchOS 9+ (Foundation only) |
| `AuriUIRenderer` | SwiftUI views, session state, detail sheets, `AuriUIHTTPClient` SSE client | Swift 6; iOS 17+, macOS 14+ (SwiftUI, Charts, Observation, [MarkdownUI](https://github.com/gonzalezreal/MarkdownUI)) |

AuriUI v1 ships 23 components plus nested detail sheets (`page`) and local pricing state (`state`):

| Group | Components |
| --- | --- |
| **Text & media** | `intro`, `header`, `hero`, `bullets`, `facts`, `steps`, `expand`, `sources` |
| **Collections & commerce** | `row`, `posters`, `grid`, `cards`, `menu`, `receipt` |
| **Data & comparison** | `stats`, `compare`, `chart` (line & grouped bar), `table` |
| **Interactive & navigation** | `list` (single-select & multi-select), `form` (`text`, `textarea`, `select`, `date`, `slider`), `chips`, `button`, `tabs`, `page` |

`chart`, `table`, and `form` are opt-in via client capability negotiation (`components` in the request contract). See [GRAMMAR.md](GRAMMAR.md) for the full syntax and sizing rules.

## Install

In Xcode, add this repository through **File → Add Package Dependencies**:

```text
https://github.com/maxgrev/AuriUI
```

Select `AuriUIRenderer` for views and `AuriUI` when your app also creates or parses documents. To develop with a local checkout:

```swift
.package(path: "../AuriUI")
```

Add the products to your target:

```swift
.product(name: "AuriUI", package: "AuriUI"),
.product(name: "AuriUIRenderer", package: "AuriUI"),
```

## Parse a document

Parse a complete document in one call:

```swift
import AuriUI

let document = AuriUIStreamingParser.parse("""
aui 1
screen lunch "Choose lunch"
state base:10 cur:USD
list "Extras" multi
item 🧀 "Cheese" val:cheese price:1.25
button primary "Order {total}" @send("Order with {selections} for {total}")
""")
```

For streamed LLM output, keep one parser per document. Each completed line updates `document`:

```swift
var parser = AuriUIStreamingParser()
parser.consume("aui 1\nintro \"Hello\"\n")
let partialDocument = parser.document
parser.consume("button \"Continue\" @nav(\"Next screen\")")
parser.finish()
if let failure = parser.failure {
    throw failure
}
let completeDocument = parser.document
```

Malformed content drops one line at a time. Invalid, misplaced, or unsupported version declarations reject the whole document (`failure` explains why and the document becomes empty). Headerless input defaults to version 1.

## Render in SwiftUI

Keep the session in your view's state, then place `AuriUIView` inside your layout. The view starts the session, displays loading and failure states, and handles local selections, form validation, confirmation, and detail sheets.

```swift
import AuriUI
import AuriUIRenderer
import SwiftUI

@MainActor
struct ExampleScreen: View {
    @State private var session = AuriUIScreenSession(answerText: """
    aui 1
    intro "Choose a drink."
    list "Drink" pick:drink
    item "Coffee" val:coffee sel
    item "Tea" val:tea
    button primary "Continue" @send("I chose {selections}")
    """, services: AuriUIHostServices(capabilities: [.send]))

    let onAction: (AuriUISurfaceAction) -> Void

    var body: some View {
        ScrollView {
            AuriUIView(session: session, accentColor: .indigo, onAction: onAction)
                .padding()
        }
    }
}
```

The callback receives `.sendToChat(prompt:)`, `.navigate(brief:parentID:)`, `.openURL(URL)`, or `.hostCapability(id:)`. Interpolation happens before the callback, so the example sends `I chose Coffee` or `I chose Tea`. Your app decides what each action does.

For a screen with its own navigation header, use `AuriUIScreenView`. For a document built directly in Swift, use `AuriUIScreenSession(document:services:)` and update it with `replaceTrustedDocument(_:)` when the host's document changes.

## Connect a provider

Supply `AuriUIHostServices` per session or per flow. This example simulates a local stream; for live generation, replace the stream closure with an adapter to your backend:

```swift
@MainActor
func makeGeneratedSession() -> AuriUIScreenSession {
    let services = AuriUIHostServices(
        capabilities: [.send],
        stream: { request in
            AsyncThrowingStream { continuation in
                let text = """
                aui 1
                intro "Your screen is ready."
                button "Continue" @send("Continue")
                """
                continuation.yield(.designing)
                continuation.yield(.delta(text))
                continuation.yield(.document(text: text, screenID: nil))
                continuation.finish()
            }
        }
    )
    return AuriUIScreenSession(brief: "Show a welcome screen", services: services)
}
```

- **Streaming lifecycle:** `request.brief` carries the requested content and `request.grounded` asks your provider to research supporting facts before generation (pass `false` when the brief supplies the facts or your provider has no search layer). Emit text chunks via `.delta`, optional verified resource maps via `.resources(["r1": url])`, and end successful runs with one `.document(text:screenID:)` containing the full validated source. Streams that finish with only deltas show an error and cannot be saved.
- **Cancellation:** cancel active tasks or network calls inside `continuation.onTermination`. Sessions cancel requests when views disappear and also expose `cancel()` and `retry()`.
- **Media & link resolution:** supply optional `imageURL(query:full:)` and `lookupURL(query:)` closures and `onTelemetry` for completion/failure events. The renderer performs no network lookups unless you supply a resolver. Return bundled file URLs for offline views. Markdown images are disabled; Markdown links enforce the same HTTP(S) and capability checks as URL actions.
- **Capabilities:** pass an empty array to disable all actions. URL actions stay disabled without a resolved target. Custom `.hostOnly` capabilities work only in trusted Swift-authored documents; model text cannot invoke them. Registrations belong to the service value, with no global registry.
- **Multi-screen flows:** keep an `AuriUISurfaceSessionStore` and call `session(parentID:brief:grounded:)` for navigation actions. The store preserves live form edits and selections when returning to a parent screen. Persist completed screens via `onSnapshot` and restore them with `AuriUISurfaceSnapshotArchive`. Background child-screen prefetching is off by default (`prefetchEnabled: true` opts in).

## Reference backend (Cloudflare + Cerebras)

The repository ships a standalone Cloudflare Worker that streams validated AuriUI documents from Cerebras:

```text
Your Apple app  →  Cloudflare Worker (auth, prompt contract, validation)  →  Cerebras
                ←  SSE stream (status, aui.delta, aui.document, done)     ←
```

Follow [Backend/README.md](Backend/README.md) to install dependencies, pick an available Cerebras model, set Worker secrets, and deploy. The Cerebras API key stays on the server. The reference backend uses a shared access token for development and private demos; production apps should replace it with user authentication and rate limits.

Connect a deployed Worker with `AuriUIHTTPClient`:

```swift
@MainActor
func makeLiveSession(
    workerURL: URL,
    authorization: @escaping @MainActor @Sendable () async throws -> String
) throws -> AuriUIScreenSession {
    let client = try AuriUIHTTPClient(baseURL: workerURL) {
        ["Authorization": try await authorization()]
    }
    return AuriUIScreenSession(
        brief: "Create a lunch picker. Soup costs $6 and salad costs $8.",
        grounded: false,
        services: client.makeServices(capabilities: [.navigation, .send])
    )
}
```

- `workerURL` is the Worker origin without `/screen`. The authorization closure returns the full header value (such as `Bearer <token>`) on every request so credentials can refresh. Never place a provider API key in client code or ship a shared demo token in a public app. HTTPS is required except for loopback development.
- `AuriUIHTTPClient` parses and validates SSE events, propagates cancellation, rejects redirects (so authorization headers cannot leak to another host), and surfaces HTTP errors, malformed streams, and incomplete documents through the renderer's failure and retry states.
- The reference backend generates strictly from facts in your brief (`grounded: false`, `capabilities: [.navigation, .send]`) and does not perform web research or image lookup. Custom backends can add grounding and resource resolvers behind the same stream interface.

You deploy the backend and pay for Cloudflare and Cerebras usage through your own accounts.

## What the host owns

Your app controls generation, image loading, link resolution, action handling, analytics, and persistence. Supplied documents and bundled demo fixtures render locally; live generation talks only to the backend you configure.

- **Detail pages (`page`):** each detail page keeps independent selections, form edits, and price state while the session is alive. A page can declare its own `state`; otherwise it inherits the document's base price and currency.
- **Form IDs:** form fields use stable IDs; if a host supplies duplicate IDs, the first field wins.
- **Snapshots:** `AuriUISurfaceSnapshotArchive` stores source documents and resolved resources. Edited form values and selection changes are not serialized into snapshots; persist those separately if your app restores in-progress state.

## Run the demo

Open [Examples/AuriUIDemo/AuriUIDemo.xcodeproj](Examples/AuriUIDemo/AuriUIDemo.xcodeproj), select the **AuriUIDemo** scheme and an iOS 17+ simulator, and run. No API key or signing team is needed for offline demos:

- **Gallery:** text, media, detail pages, charts, tables, tabs, and expandable sections.
- **Interactive:** live `Decimal` selection totals, all five form field types, local validation, confirmation sheets, and registered host actions.
- **Streaming:** incremental line-by-line rendering, final document replacement, truncation handling, provider errors, retry, and cancellation.
- **Live:** connects `AuriUIHTTPClient` to your deployed Cloudflare Worker with an in-memory access token and supports multi-screen navigation.

See [Examples/AuriUIDemo/README.md](Examples/AuriUIDemo/README.md) for demo setup and UI test details.

## Contract and tests

`Contract/auriui-v1.json` is the normative manifest for component syntax, prompt instructions, validator keywords, and client capability gates. Regenerate and verify the Swift and JavaScript bindings from the package root:

```sh
node Scripts/generate-contract.mjs
node Scripts/generate-contract.mjs --check
```

Backend authors can import `Contract/auriui-v1.generated.mjs` to stay in lockstep with the Swift parser. Edit `Contract/auriui-v1.json` and [GRAMMAR.md](GRAMMAR.md) together instead of editing generated files directly.

Run the Swift package tests (macOS with Swift 6):

```sh
swift test
```

Run the Cloudflare Worker tests and bundle check:

```sh
cd Backend && npm ci && npm test && npm run check
```

In Xcode, run **Product → Test** on the `AuriUIDemo` scheme for simulator integration and UI tests. See [CONTRIBUTING.md](CONTRIBUTING.md) for the full workflow.

## Repository layout

```text
Sources/AuriUI/          Foundation-only lexer, streaming parser, state, snapshots, generated contract
Sources/AuriUIRenderer/  SwiftUI component views, sessions, prefetcher, AuriUIHTTPClient
Contract/                Normative auriui-v1.json manifest and generated JS contract
Scripts/                 Cross-language Swift/JS contract generator and parity checker
Backend/                 Deployable Cloudflare Worker + Cerebras SSE reference backend
Examples/AuriUIDemo/     Standalone iOS demo app (Gallery, Interactive, Streaming, Live) + UI tests
Tests/                   Core parser, resilience, pricing, contract parity, renderer, and HTTP tests
```

## License

Copyright (c) 2026 Feanor Labs.

AuriUI, including the Swift packages, demo app, and reference backend, is licensed under the Apache License, Version 2.0 (`SPDX-License-Identifier: Apache-2.0`). See [LICENSE](LICENSE). Dependencies retain their own licenses.

### Optional credit

If you use AuriUI, we'd appreciate a credit in your app's About screen:

> Built with AuriUI by Feanor Labs.

This credit is optional and is not a condition of the license. The license's requirements to preserve applicable legal notices still apply.
