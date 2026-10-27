# Contributing

Use Swift 6 and an Xcode version that supports it. Keep the core target free of
UI, networking, and app dependencies. Put SwiftUI and host integration in
`AuriUIRenderer`.

Keep the reference backend independent of any host app. Its grammar and
validator use the package contract. Keep credentials out of source and
fixtures. Do not depend on host-specific services or files outside the
checkout.

1. Change the smallest affected part of the package.
2. Add a regression test for a behavior change. Prefer tests that use public
   APIs and real document shapes.
3. Run the package tests and the demo's relevant simulator tests.
4. Include screenshots for visible changes and describe any API change.

## Change the format

Update `Contract/auriui-v1.json` and `GRAMMAR.md` together. Then run:

```sh
node Scripts/generate-contract.mjs
node Scripts/generate-contract.mjs --check
```

Do not edit generated Swift or JavaScript files directly. Add a syntax fixture
and parser test for new behavior. Preserve headerless v1 parsing and recovery
from ordinary malformed lines. Breaking format changes need a new protocol
version and an explicit migration plan.

## Check a change

Run `swift test` from this directory for package coverage. Open
`Examples/AuriUIDemo/AuriUIDemo.xcodeproj` and run the `AuriUIDemo` test action
for iOS integration and UI tests. The demo includes the core and renderer test
sources; it requires no backend or secrets.

The HTTP client tests use a controlled transport, and the Live demo UI tests
start a local HTTP fixture server. They exercise streaming, failures, retry,
cancellation, and navigation without paid model calls. A real Cerebras smoke
test is separate: follow `Backend/README.md`, run the backend, then use the
demo's Live tab. Never commit test credentials.

For backend changes, run `npm ci`, `npm test`, and `npm run check` from
`Backend/`. The last command builds the Worker for deployment without
publishing it. Keep the Worker response events and Swift HTTP client tests in
sync when changing the transport contract.

If you change the demo's project configuration, edit its `project.yml`, run
`xcodegen generate` from that directory, and commit the generated project.
Consumers can open the committed project without installing XcodeGen.

## Report an issue

Include the OS and Xcode versions, a small document that reproduces the issue,
the expected result, and the actual result. Remove private data and credentials
from fixtures and logs.

Contributions use the project's [Apache-2.0 license](LICENSE).
