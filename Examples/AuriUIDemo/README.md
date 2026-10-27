# AuriUI Demo

A standalone iOS app that imports only `AuriUI` and `AuriUIRenderer`. It uses the local package at `../..`, so the demo works when the whole package moves into its own repository.

Open `AuriUIDemo.xcodeproj`, choose the **AuriUIDemo** scheme, and run on an iOS 17 or later simulator. No API key or development team is needed for simulator builds or the offline examples. Xcode resolves the renderer's MarkdownUI dependency on the first build.

- **Gallery** covers text, media, detail pages, charts, tables, tabs, and expansion.
- **Interactive** shows exact selection totals, all five form field types, validation and confirmation, and a registered host action.
- **Streaming** shows incremental content, a complete final document, truncation, a provider error, retry, and cancellation.
- **Live** connects the package's `AuriUIHTTPClient` to a Worker you deploy, generates screens from your descriptions, and follows generated navigation actions.

Gallery, Interactive, and Streaming bundle every document and image. Their data is fictional, and they work offline. Link and send actions appear in the **Host result** panel; navigation actions open a host-supplied screen. These three tabs never contact a backend or open external websites.

## Live setup

1. Follow [the backend setup guide](../../Backend/README.md) to deploy your own Cloudflare Worker. Store `CEREBRAS_API_KEY` and `BACKEND_TOKEN` as Worker secrets. Set the supported Cerebras model in the Worker configuration.
2. Open **Live** and enter the Worker origin, such as `https://your-worker.workers.dev`. Do not add `/screen`: the Swift adapter appends it. For a local Worker, use `http://127.0.0.1:8787` in the simulator. Deployed Workers use HTTPS; the app's only transport exception permits local networking.
3. Enter the Worker's `BACKEND_TOKEN` in **Backend access token**. Never enter your Cerebras API key in the app. The URL and token stay in memory; **Clear connection** removes them and the current live sessions. The demo does not store credentials in preferences, files, or the Keychain.
4. Describe a screen and include the facts it should use, then tap **Generate**. The reference backend generates from your text; it does not search the web or provide images. Each Generate, retry, restart, or generated navigation action can use your provider quota.

The ready screen stays interactive. A generated navigation action creates a child through the same HTTP client and `AuriUISurfaceSessionStore`; returning to the parent keeps its selections and form edits. A send action only records **Ready to send** in the **Host result** panel. It does not trigger another request. Your own app decides what a send action should do.

**Cancel** stops an in-flight request. Leaving Live during generation also stops it; returning does not send another request. **Restart** sends it again. An HTTP or stream failure shows the renderer's retry control. Child screens reuse the connection configured for that live flow. Prefetching stays off, so the demo sends requests only after these explicit actions.

The backend token is a simple access gate for development and evaluation. For a shipped app, replace a bundled shared token with your own user authentication and server-side authorization, quotas, and abuse controls. Keep all model-provider credentials on the server.

The `DemoServices` factory in `Sources/DemoSamples.swift` provides offline image and link resolvers. `Sources/DemoLiveView.swift` shows the complete HTTP integration, including refreshed request headers, supported capabilities, navigation, and host handoffs. Both root and child live sessions use `grounded: false`, as required by the reference backend.

Use **Product → Test** to run the package's core and renderer tests, resource integration checks, setup validation, and demo UI tests. The offline UI tests verify visible action results, total changes, form confirmation, detail pages, tab content, chart data, and each streaming outcome. Live UI tests start a loopback HTTP fixture in the test runner and exercise real adapter requests, authorization failure, retry, cancellation, child navigation, and preserved selections. No cloud account, provider key, or external fixture server is needed for these deterministic tests. They do not prove live model output quality; use the Live tab with your deployed Worker for that check.

The UI fixture prefill is available only in Debug builds, behind the explicit `-AuriUIDemoLiveFixture` launch argument and `AURIUI_DEMO_WORKER_URL`, `AURIUI_DEMO_ACCESS_TOKEN`, and `AURIUI_DEMO_PROMPT` launch environment values. Release builds ignore it. No production endpoint or real token is included in the project.

The generated Xcode project is included. If you change `project.yml`, install [XcodeGen](https://github.com/yonaskolb/XcodeGen) and run `xcodegen generate` from this directory.
