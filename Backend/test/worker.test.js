import assert from "node:assert/strict"
import test from "node:test"
import { createWorker } from "../src/index.js"
import { buildAuiInstructions, validateAuiText } from "../src/aui.js"

const token = "test-only-token-with-at-least-32-characters"
const env = { BACKEND_TOKEN: token, CEREBRAS_API_KEY: "test-key", CEREBRAS_MODEL: "test-model" }
const document = 'aui 1\nscreen practice "Practice plan" tint:blue\nheader 🎵 "Warm up"\nintro "Practice scales for 10 minutes."\nbutton "Continue" @nav("Create the next practice step")'
const body = { brief: "A music practice plan", grounded: false }
function request(value = body, options = {}) {
  return new Request("https://example.test/screen", {
    method: "POST", headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" }, body: JSON.stringify(value), ...options,
  })
}
function chunk(text, finish = null) {
  return `data: ${JSON.stringify({ choices: [{ delta: { content: text }, finish_reason: finish }] })}\n\n`
}
function provider(text = document, finish = "stop") {
  return new Response(chunk(text, finish) + "data: [DONE]\n\n", { headers: { "Content-Type": "text/event-stream" } })
}
async function output(worker, input = request(), config = env) {
  const response = await worker.fetch(input, config)
  return { status: response.status, text: await response.text() }
}
function events(text) {
  return text.trim().split("\n\n").map((frame) => {
    const [event, data] = frame.split("\n")
    return { event: event.slice(7), data: JSON.parse(data.slice(6)) }
  })
}

test("health describes unavailable resources without exposing configuration", async () => {
  const response = await createWorker().fetch(new Request("https://example.test/health"), env)
  assert.deepEqual(await response.json(), { status: "ok", protocol: "aui 1", generation: "cerebras", grounding: false, images: false, url_lookup: false })
})

test("auth rejects missing and wrong credentials before contacting Cerebras", async () => {
  let calls = 0
  const worker = createWorker(() => { calls++; throw new Error("must not fetch") })
  for (const authorization of [undefined, "Bearer wrong", "Basic invalid"]) {
    const input = request()
    if (authorization) input.headers.set("Authorization", authorization)
    else input.headers.delete("Authorization")
    assert.equal((await worker.fetch(input, env)).status, 401)
  }
  assert.equal(calls, 0)
  assert.equal((await worker.fetch(request(), { ...env, BACKEND_TOKEN: "short" })).status, 503)
  assert.equal((await worker.fetch(request(), { ...env, CEREBRAS_MODEL: "" })).status, 503)
})

test("rejects malformed, oversized and unsupported requests before inference", async () => {
  const worker = createWorker(() => { throw new Error("must not fetch") })
  for (const value of [null, { ...body, brief: " " }, { ...body, brief: "x".repeat(8001) }, { brief: "test" }, { ...body, locale: 3 }, { ...body, capabilities: [] }, { ...body, capabilities: [{ id: "url", description: "URL" }] }, { ...body, components: ["not-a-component"] }]) {
    assert.equal((await worker.fetch(request(value), env)).status, 400)
  }
  assert.equal((await worker.fetch(request({ ...body, grounded: true }), env)).status, 422)
  assert.equal((await worker.fetch(request(body, { body: "[" }), env)).status, 400)
  assert.equal((await worker.fetch(request(body, { body: "x".repeat(32769) }), env)).status, 413)
  assert.equal((await worker.fetch(request(body, { headers: { Authorization: `Bearer ${token}` } }), env)).status, 415)
})

test("streams valid deltas then authoritative document and successful done", async () => {
  const worker = createWorker(async (url, options) => {
    assert.equal(url, "https://api.cerebras.ai/v1/chat/completions")
    assert.equal(options.headers.Authorization, "Bearer test-key")
    const upstream = JSON.parse(options.body)
    assert.equal(upstream.model, "test-model")
    assert.equal(upstream.stream, true)
    assert.equal(upstream.max_completion_tokens, 3000)
    assert.equal(upstream.reasoning_effort, undefined)
    assert.match(upstream.messages[0].content, /This host has no image, web research, or URL lookup service/)
    return provider()
  })
  const result = await output(worker)
  const received = events(result.text)
  assert.equal(result.status, 200)
  assert.deepEqual(received.map(({ event }) => event), ["status", "aui.delta", "aui.document", "done"])
  assert.equal(received[2].data.text, document)
  assert.equal(received[2].data.screen_id, "practice")
  assert.deepEqual(received[3].data, { outcome: "screen", grounded: false })
})

test("handles UTF-8 and CRLF split across upstream chunks", async () => {
  const bytes = new TextEncoder().encode((chunk(document, "stop") + "data: [DONE]\n\n").replaceAll("\n", "\r\n"))
  let offset = 0
  const worker = createWorker(async () => new Response(new ReadableStream({
    pull(controller) {
      if (offset === bytes.length) controller.close()
      else controller.enqueue(bytes.slice(offset, ++offset))
    },
  }), { headers: { "Content-Type": "text/event-stream" } }))
  assert.equal(events((await output(worker)).text).at(-1).data.outcome, "screen")
})

test("accepts explicit stop at EOF but never turns dropped or truncated output into success", async () => {
  for (const [finish, outcome] of [[null, "dropped_stream"], ["length", "truncated_screen"], ["content_filter", "dropped_stream"]]) {
    const received = events((await output(createWorker(async () => provider(document, finish)))).text)
    assert.equal(received.at(-1).data.outcome, outcome)
    assert.ok(received.some(({ event }) => event === "error"))
    assert.ok(!received.some(({ event }) => event === "aui.document"))
  }
  const worker = createWorker(async () => new Response(chunk(document, "stop"), { headers: { "Content-Type": "text/event-stream" } }))
  assert.equal(events((await output(worker)).text).at(-1).data.outcome, "screen")
})

test("rejects invalid grammar, versions, unsupported resources and unavailable actions", async () => {
  for (const text of [document.replace("aui 1", "aui 2"), document + '\nhero img:"imaginary" "Image"', document + '\ngrid "Choices"\nitem 🍎 "Apple" img:"apple"', document + '\nbutton "Open" @url(find:"fake")', document + '\nbutton "Buy" @purchase("test")', document + '\ninvalid "line"', "aui 1\nscreen empty \"Empty\""]) {
    const received = events((await output(createWorker(async () => provider(text)))).text)
    assert.equal(received.at(-1).data.outcome, "invalid_screen")
    assert.ok(!received.some(({ event }) => event === "aui.document"))
  }
})

test("allows action-like syntax inside display text and quoted action arguments", async () => {
  const text = 'aui 1\nscreen lesson "CSS lesson"\nintro "Use @media (max-width: 600px) to adapt the layout."\nbutton "Continue" @nav("Explain \\"@media (max-width: 600px)\\" with examples")'
  const received = events((await output(createWorker(async () => provider(text)))).text)
  assert.equal(received.at(-1).data.outcome, "screen")
  assert.equal(received.find(({ event }) => event === "aui.document").data.text, text)
})

test("only accepts a generated table when the client advertises table support", async () => {
  const table = 'aui 1\nscreen practice "Practice"\ntable "Tasks"\ntcol "Task"\ntcol "Minutes"\ntrow "Scales" "10"'
  const worker = createWorker(async () => provider(table))
  for (const components of [undefined, [], ["chart", "form"]]) {
    const received = events((await output(worker, request({ ...body, components }))).text)
    assert.equal(received.at(-1).data.outcome, "invalid_screen")
    assert.ok(!received.some(({ event }) => event === "aui.document"))
  }
  const received = events((await output(worker, request({ ...body, components: ["table"] }))).text)
  assert.equal(received.at(-1).data.outcome, "screen")
  assert.equal(received.find(({ event }) => event === "aui.document").data.text, table)
})

test("allows resource-like syntax inside display text", async () => {
  const text = 'aui 1\nscreen lesson "Fields"\nintro "The url: field contains the address."\nintro "The img: field contains an image query, such as \\"img:apple\\"."'
  const received = events((await output(createWorker(async () => provider(text)))).text)
  assert.equal(received.at(-1).data.outcome, "screen")
  assert.equal(received.find(({ event }) => event === "aui.document").data.text, text)
})

test("validates forms against the supplied form-capable actions", async () => {
  const form = 'aui 1\nscreen plan "Plan"\nform practice "Practice" cap:send confirm:"Use this plan?"\nfield text instrument "Instrument" required\nsubmit "Plan" @send("Plan {instrument}")'
  const input = request({ ...body, capabilities: [{ id: "send", description: "Follow-up", accepts_form_input: true }], components: ["form"] })
  const received = events((await output(createWorker(async () => provider(form)), input)).text)
  assert.equal(received.at(-1).data.outcome, "screen")
})

test("provider failures never expose provider bodies, keys or thrown messages", async () => {
  for (const fetcher of [async () => new Response("SECRET provider details", { status: 500 }), async () => { throw new Error("SECRET provider details") }, async () => new Response("not SSE", { headers: { "Content-Type": "application/json" } })]) {
    const result = await output(createWorker(fetcher))
    assert.doesNotMatch(result.text, /SECRET|test-key/)
    assert.equal(events(result.text).at(-1).data.outcome, "provider_error")
  }
})

test("malformed and oversized events fail with bounded output", async () => {
  for (const payload of ["data: {broken}\n\n", `data: ${"x".repeat(65537)}\n\n`]) {
    const worker = createWorker(async () => new Response(payload, { headers: { "Content-Type": "text/event-stream" } }))
    const result = await output(worker)
    assert.ok(result.text.length < 1000)
    assert.ok(!result.text.includes("event: aui.document"))
  }
})

test("enforces separate document and total upstream limits across small events", async () => {
  const cases = [
    chunk("x".repeat(32_000)) + chunk("x".repeat(32_000)) + chunk("x".repeat(32_000), "stop"),
    Array.from({ length: 20 }, () => `data: ${JSON.stringify({ choices: [{ delta: { reasoning: "x".repeat(30_000) } }] })}\n\n`).join(""),
  ]
  for (const payload of cases) {
    const worker = createWorker(async () => new Response(payload, { headers: { "Content-Type": "text/event-stream" } }))
    const result = await output(worker)
    assert.equal(events(result.text).at(-1).data.outcome, "truncated_screen")
    assert.ok(!result.text.includes("event: aui.document"))
    assert.ok(result.text.length < 100_000)
  }
})

test("cancelling the downstream stream aborts inference and cancels its reader", async () => {
  let signal
  let cancelled = false
  const worker = createWorker(async (_, options) => {
    signal = options.signal
    return new Response(new ReadableStream({
      start(controller) { controller.enqueue(new TextEncoder().encode(chunk("aui 1\n"))) },
      cancel() { cancelled = true },
    }), { headers: { "Content-Type": "text/event-stream" } })
  })
  const response = await worker.fetch(request(), env)
  const reader = response.body.getReader()
  await reader.read() // status
  await reader.read() // first delta
  await reader.cancel()
  assert.equal(signal.aborted, true)
  assert.equal(cancelled, true)
})

test("request cancellation aborts a stalled upstream read", async () => {
  const abort = new AbortController()
  const worker = createWorker(async () => new Response(new ReadableStream({}), { headers: { "Content-Type": "text/event-stream" } }))
  const response = await worker.fetch(request(body, { signal: abort.signal }), env)
  const result = response.text()
  abort.abort()
  const received = events(await result)
  assert.equal(received.at(-1).data.outcome, "timeout")
})

test("shared prompt retains production resources by default and validates the same grammar", () => {
  assert.match(buildAuiInstructions({}), /ALWAYS get img/)
  assert.doesNotMatch(buildAuiInstructions({ resourceMode: "none" }), /ALWAYS get img/)
  assert.equal(validateAuiText(document).ok, true)
})
