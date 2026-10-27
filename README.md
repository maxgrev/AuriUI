# AuriUI

Render interactive native screens from small text documents. AuriUI parses
complete documents or streamed chunks, keeps form and selection state locally,
and returns actions to your app.

This repository includes the parser, native renderer, streaming HTTP client,
and a deployable [Cloudflare/Cerebras reference backend](Backend/README.md).
The standalone demo has offline examples and a Live mode for your own backend.

The package includes two libraries:

| Product | Purpose | Requirements |
| --- | --- | --- |
| `AuriUI` | Documents, streaming parser, forms, selections, snapshots | Swift 6; iOS 16+, macOS 13+, watchOS 9+ |
| `AuriUIRenderer` | SwiftUI components, sessions, host integration | iOS 17+, macOS 14+ |

The core target depends only on Foundation. The renderer uses Apple's SwiftUI,
Charts, and Observation frameworks and [MarkdownUI](https://github.com/gonzalezreal/MarkdownUI).

## Install

In Xcode, add this repository through **File → Add Package Dependencies**.
Select `AuriUIRenderer` for views and `AuriUI` when your app also creates or
parses documents. To develop with a local checkout:

```swift
.package(path: "../AuriUI")
```

Add the products to the target that uses them:

```swift
.product(name: "AuriUI", package: "AuriUI"),
.product(name: "AuriUIRenderer", package: "AuriUI"),
```

## Parse a document

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

For streamed output, keep one parser per document. Each completed line updates
`document`:

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

Malformed content drops one line at a time. Invalid, misplaced, or unsupported
version declarations reject the whole document. `failure` explains why; the
document becomes empty. Headerless input uses version 1.

## Render in SwiftUI

Keep the session in your view's state, then place `AuriUIView` inside your
layout. The view starts the session, displays loading and failure states, and
handles local selection, form validation, and detail sheets.

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

The callback receives `.sendToChat(prompt:)`, `.navigate(brief:parentID:)`,
`.openURL(URL)`, or `.hostCapability(id:)`. The names describe the actions;
your app chooses their effects. For example, a send action can update a search
query or add a message to a conversation. Interpolation happens before the
callback, so the example sends `I chose Coffee` or `I chose Tea`.

For a screen with its own navigation header, use `AuriUIScreenView` instead.
For a document built directly in Swift, use
`AuriUIScreenSession(document:services:)`. Update that session with
`replaceTrustedDocument(_:)` when the host's document changes.

## Connect a provider

Supply services per session or per flow. This example simulates a local stream;
it does not call a model. For live generation, replace its stream closure with
an adapter to your backend:

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

`request.brief` is the requested content, and `request.grounded` asks your
provider to research supporting facts before generation. Use `false` when
the brief already supplies the facts or the provider has no research service.
Send text chunks through `.delta`. Send resource references through
`.resources(["r1": url])` before completion. End successful output with one
`.document(text:screenID:)` containing the full, validated source, then finish
the stream. The complete document replaces its streamed prefix and ends the
session's request. A stream that ends with only deltas displays an error and
cannot be saved as a completed screen.

When your adapter starts a task or network request, cancel that work from the
stream continuation's `onTermination` handler. Sessions cancel requests when
their views disappear. A manually owned session also exposes `cancel()` and
`retry()`.

Optional `imageURL(query:full:)` and `lookupURL(query:)` closures return URLs
from your app's image service or search provider. `onTelemetry` receives
completion and failure events. The renderer performs none of these lookups
unless you supply a resolver. If your image resolver returns an HTTP(S) URL,
the renderer downloads that image; return bundled file URLs for offline views.
Markdown images are disabled; use AuriUI's image components with your image
resolver. Links in Markdown follow the same HTTP(S) URL and capability checks
as other URL actions.

Capabilities control which actions and forms the session enables. Pass an
empty array to disable all actions. URL actions also need a resolved target;
missing resource references and lookups without a resolver stay disabled.
Custom `.hostOnly` capabilities are for
trusted Swift-authored documents; model text cannot create them. Registrations
belong to the service value you pass, so separate apps, accounts, or flows do
not share a global registry.

For a flow with generated child screens, keep an `AuriUISurfaceSessionStore`
and call `session(parentID:brief:grounded:)` for each navigation action. The
store preserves live form edits and selections when a screen is reopened.
Use its `onSnapshot` callback to save completed screens and pass an
`AuriUISurfaceSnapshotArchive` when restoring them. Optional prefetching is off
by default; set `prefetchEnabled: true` only when your provider should compose
candidate child screens in the background.

## Generate with Cloudflare and Cerebras

The reference backend uses your Cloudflare account and Cerebras API key:

```text
Your iOS app → your Cloudflare Worker → Cerebras
            ← streamed AuriUI document ←
```

Follow the [backend setup guide](Backend/README.md) to install dependencies,
select an available Cerebras model, set the Worker secrets, and deploy. The
Cerebras key stays on the server. The app receives only access credentials for
your Worker. The reference backend uses a shared access token for development
and private demos; production apps should supply their own user authentication
and usage controls.

Connect the deployed Worker with the included Swift client:

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

`workerURL` is the Worker base URL, without `/screen`. The authorization
closure returns the complete header value, such as `Bearer <access token>`,
and runs again on each request so your app can refresh credentials. Do not
put a Cerebras API key in this closure or ship a shared demo token in a public
app. HTTPS is required except for loopback development servers.

`AuriUIHTTPClient` streams and validates SSE events, refreshes request headers,
and propagates cancellation. It reports HTTP errors, malformed streams, and
incomplete documents through the renderer's failure and retry states. It
rejects redirects so authorization cannot move to another endpoint.

The reference backend generates from the facts in your prompt. It does not
search the web or resolve images and links. For both root and child screens,
use `grounded: false` and `client.makeServices(capabilities: [.navigation, .send])`.
The HTTP client's default capabilities also allow URL actions for custom
backends; the reference backend rejects them and external grounding requests.
You can add research and resource services behind the same stream interface
and inject image/link resolvers.

Cerebras supplies inference; Cloudflare hosts orchestration, validation, and
stream delivery. The renderer preserves progressive rendering, but does not
supply inference capacity or guarantee a generation latency. Provider, model,
grounding, and network choices still matter. Optional child-screen prefetching
can reuse generated results; enable it explicitly when wanted.

You deploy the backend and pay for Cloudflare and Cerebras usage through your
own accounts.

## What the host owns

The app decides how to generate documents, load images, resolve links, handle
actions, record analytics, and store snapshots. Supplied documents and bundled
demo examples render locally. Live AI generation uses your configured backend;
your app supplies its authentication and configuration.

The component catalog includes text, images, tiles, menus, cards, comparisons,
charts, tables, tabs, detail pages, selection lists, receipts, and forms. Read
[the grammar](GRAMMAR.md) for the supported shapes and limits. Prices use
`Decimal`; the client computes totals. Form fields use stable IDs, and the
first field wins if a host supplies the same ID more than once.

Each detail page keeps its own selections, form edits, and price state.
Reopening a page in the same session preserves those edits. A page can declare
its own `state`; otherwise, it inherits the document's base price and currency.

Snapshots store source documents and resolved resources. They do not store
edited form values or selection changes; persist those separately if your app
needs to restore them.

## Run the demo

Open [Examples/AuriUIDemo/AuriUIDemo.xcodeproj](Examples/AuriUIDemo/AuriUIDemo.xcodeproj),
select the `AuriUIDemo` scheme and an iOS simulator, then run. The standalone
Gallery, Interactive, and Streaming use bundled fixtures and local services,
so they work without credentials. The Live tab connects to your Worker with
an access token held only for the current app session. Enter a prompt with
the screen's facts, generate it, and follow its navigation actions. The test
targets exercise the core, renderer, and HTTP client through the package.

## Contract and tests

`Contract/auriui-v1.json` is the source of truth for supported syntax. Generate
the Swift and JavaScript contracts from the package directory:

```sh
node Scripts/generate-contract.mjs
node Scripts/generate-contract.mjs --check
```

Backend authors can import `Contract/auriui-v1.generated.mjs` to use the same
component catalog and prompt grammar. This file is generated; edit the JSON
manifest and [grammar](GRAMMAR.md) together instead.

Run the package tests on macOS with Xcode's Swift 6 toolchain:

```sh
swift test
```

In Xcode, run the `AuriUIDemo` test action for simulator integration and UI
coverage. See [CONTRIBUTING.md](CONTRIBUTING.md) for the development workflow.

## License

Copyright (c) 2026 Feanor Labs.

AuriUI, including the Swift packages, demo app, and reference backend, is
licensed under the Apache License, Version 2.0
(`SPDX-License-Identifier: Apache-2.0`). See [LICENSE](LICENSE).
Dependencies retain their own licenses.

### Optional credit

If you use AuriUI, we'd appreciate a credit in your app's About screen:

> Built with AuriUI by Feanor Labs.

This credit is optional and is not a condition of the license. The license's
requirements to preserve applicable legal notices still apply.
