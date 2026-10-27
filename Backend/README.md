# AuriUI Cloudflare/Cerebras backend

Generate interactive native screens with one streaming request. Cloudflare runs the Worker; Cerebras generates AuriUI text; the Swift renderer displays the stream as it arrives. This folder runs from a standalone AuriUI checkout.

This backend provides generation, validation, and streaming for text, selections, forms, tabs, charts, and generated child screens. Supply all needed facts and numbers in the brief and set `grounded: false`. Web research, image search, source resolution, conversation storage, user authentication, and provider failover are outside its scope. Requests with `grounded: true` fail explicitly.

## Local setup

Install Node.js 22 or later and obtain a Cerebras API key. From the package root:

```sh
cd Backend
npm ci
cp .dev.vars.example .dev.vars
openssl rand -hex 32
```

Edit the ignored `.dev.vars`: set `CEREBRAS_API_KEY` to your server key and `BACKEND_TOKEN` to the generated random value. Then list models available to your account:

```sh
npm run models
```

Set `CEREBRAS_MODEL` in `.dev.vars` to one of those IDs. No default model is hard-coded because availability changes. For a model supporting disabled reasoning, set `CEREBRAS_REASONING_EFFORT="none"` to reduce generation latency. Check the selected model's [reasoning options](https://inference-docs.cerebras.ai/api-reference/chat-completions) first; unsupported values fail at the provider.

```sh
npm run dev
```

Wrangler prints the local URL, normally `http://localhost:8787`. In the demo's Live tab, enter that URL and your **backend token**, then generate a practice plan or another screen. The iOS Simulator can reach the Mac's localhost; a physical device needs a reachable HTTPS deployment. The demo allows HTTP only on loopback for local development. The Cerebras key stays on the server.

`GET /health` reports protocol and feature support. It does not contact Cerebras or prove credentials work. The first generation verifies those credentials.

## Deploy

Choose a unique Worker `name` and set `vars.CEREBRAS_MODEL` in `wrangler.jsonc`. Optionally add `CEREBRAS_REASONING_EFFORT` for a model that supports it. Keep both API keys and backend tokens out of that file.

```sh
npx wrangler login
npm run secret:cerebras
npm run secret:backend
npm run deploy
```

The secret commands prompt for values. Use the generated token (at least 32 characters) for `BACKEND_TOKEN`. `.dev.vars` configures local development only; Wrangler secrets configure the deployed Worker. Update the demo endpoint to the deployed HTTPS URL.

The static backend token is intended for private demos and server-to-server calls. Do not embed it in a public app: anyone can extract an app's shared credential. Before distributing your app, replace `authorize` in `src/index.js` with validation of short-lived user tokens and add per-user quotas or rate limiting. `AuriUIHTTPClient` accepts an async authorization-header provider so your app can refresh user credentials.

## Swift integration

Use `AuriUIHTTPClient` from `AuriUIRenderer`, pass the base URL and a header provider, and use its `stream` closure in `AuriUIHostServices`. See the [package guide](../README.md) for a complete example and the [demo](../Examples/AuriUIDemo/README.md) for a runnable app. Advertise `nav` and/or `send` capabilities. The host decides what a follow-up action does; it must not treat generated text as permission to perform payments or account changes.

To add web research or images later, implement those server services first, return their verified resources before the final document, and supply matching image/URL resolvers on the client. Change the explicit no-resource prompt and validation policy together. Merely enabling `grounded` or adding a URL capability does not add a service.

## Wire contract

`POST /screen` requires `Authorization: Bearer <backend-token>` and `Content-Type: application/json`:

```json
{
  "brief": "Create a 20 minute piano practice plan with three phases and follow-up choices.",
  "grounded": false,
  "locale": "en_US",
  "capabilities": [
    { "id": "nav", "description": "Open a generated child screen", "accepts_form_input": true },
    { "id": "send", "description": "Send a follow-up to the host app", "accepts_form_input": true }
  ],
  "components": ["form", "chart", "table"]
}
```

`acceptsFormInput` is accepted as an alias for `accepts_form_input`. Missing capabilities default to `nav` and `send`. Missing `components` means no optional extensions. Unknown component IDs or actions fail before inference.

The response uses SSE event names and JSON payloads:

| Event | Payload |
| --- | --- |
| `status` | `{"phase":"designing"}` |
| `aui.delta` | `{"text":"..."}` |
| `aui.document` | `{"text":"aui 1\n...","screen_id":"...","sections":3,"dropped_lines":0}` |
| `error` | `{"message":"A safe, retryable explanation."}` |
| `done` | `{"outcome":"screen","grounded":false}` on success; another outcome on failure |

The reference emits no `aui.resources`, since it has no resource service. A final document replaces the preview and appears only after Cerebras reports `finish_reason: "stop"` and validation succeeds. Dropped streams, token limits, invalid documents, unsupported resources, timeouts, and provider errors emit `error` plus a failing `done`. HTTP validation/auth failures return `{"error":"..."}` with a non-2xx status.

The Worker caps requests at 32 KiB, briefs at 8,000 UTF-16 code units, generated documents and individual events at 64 KiB, upstream bytes at 512 KiB, and generation at 30 seconds. It uses pull-based streaming with backpressure; cancellation aborts the provider request. It never logs prompts, keys, generated content, or upstream error bodies. There is no automatic provider retry, so one request does not silently incur multiple generations.

## Checks

```sh
npm test
npm run check
npm run types
```

Tests mock the provider and cover authentication, request limits, split UTF-8/SSE frames, valid output, forms, truncated streams, malformed output, unavailable resources, cancellation, and error redaction. `check` verifies the generated contract and bundles the Worker without deploying. `types` derives local Worker bindings from Wrangler configuration.

The backend is Apache-2.0 under the [package license](../LICENSE). Cloudflare and Cerebras accounts, service terms, model access, and usage costs are separate from the source license.

References: [Cloudflare secrets](https://developers.cloudflare.com/workers/configuration/secrets/), [streaming](https://developers.cloudflare.com/workers/runtime-apis/streams/), [Cerebras model list](https://inference-docs.cerebras.ai/api-reference/models/list-models), and [chat completion protocol](https://inference-docs.cerebras.ai/api-reference/chat-completions).
