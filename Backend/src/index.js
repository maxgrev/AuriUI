import { createHash, timingSafeEqual } from "node:crypto"
import { buildAuiInstructions, unquotedAuiLine, validateAuiText } from "./aui.js"
import { AUI_COMPONENTS } from "../../Contract/auriui-v1.generated.mjs"

const encoder = new TextEncoder()
const LIMITS = Object.freeze({ request: 32_768, brief: 8_000, document: 65_536, event: 65_536, upstream: 524_288, timeout: 30_000 })
const supportedComponents = new Set(AUI_COMPONENTS.map(({ id }) => id))
const endpoint = "https://api.cerebras.ai/v1/chat/completions"

class PublicError extends Error {
  constructor(message, outcome = "provider_error", status = 400) {
    super(message)
    this.outcome = outcome
    this.status = status
  }
}

function json(value, status = 200) {
  return Response.json(value, { status, headers: { "Cache-Control": "no-store" } })
}

// This is the only authentication boundary. Replace it with your own short-lived
// user-token verification and per-user quota before shipping a public client.
export function authorize(request, env) {
  if (!env.BACKEND_TOKEN || env.BACKEND_TOKEN.length < 32) return false
  const authorization = request.headers.get("Authorization") ?? ""
  const expected = `Bearer ${env.BACKEND_TOKEN}`
  return timingSafeEqual(createHash("sha256").update(authorization).digest(), createHash("sha256").update(expected).digest())
}

async function read(reader, signal) {
  signal.throwIfAborted()
  let rejectAbort
  const aborted = new Promise((_, reject) => { rejectAbort = () => reject(signal.reason) })
  signal.addEventListener("abort", rejectAbort, { once: true })
  try {
    return await Promise.race([reader.read(), aborted])
  } finally {
    signal.removeEventListener("abort", rejectAbort)
  }
}

async function requestBody(request) {
  if (!request.headers.get("Content-Type")?.toLowerCase().startsWith("application/json")) {
    throw new PublicError("Send an application/json request.", "invalid_request", 415)
  }
  if (Number(request.headers.get("Content-Length")) > LIMITS.request || !request.body) {
    throw new PublicError("The request is empty or too large.", "invalid_request", 413)
  }
  const reader = request.body.getReader()
  const signal = AbortSignal.any([request.signal, AbortSignal.timeout(10_000)])
  const decoder = new TextDecoder("utf-8", { fatal: true })
  let text = ""
  let count = 0
  try {
    while (true) {
      const { value, done } = await read(reader, signal)
      if (done) break
      count += value.byteLength
      if (count > LIMITS.request) throw new PublicError("The request is too large.", "invalid_request", 413)
      text += decoder.decode(value, { stream: true })
    }
    text += decoder.decode()
    return validateRequest(JSON.parse(text))
  } catch (error) {
    if (error instanceof PublicError) throw error
    throw new PublicError("The request must contain valid JSON and finish within 10 seconds.", "invalid_request")
  } finally {
    await reader.cancel().catch(() => {})
    reader.releaseLock()
  }
}

export function validateRequest(body) {
  if (!body || typeof body !== "object" || Array.isArray(body)
      || typeof body.brief !== "string" || !body.brief.trim() || body.brief.length > LIMITS.brief) {
    throw new PublicError("brief must contain 1–8000 characters.", "invalid_request")
  }
  if (body.grounded === true) {
    throw new PublicError("This reference backend has no web research service. Set grounded to false and supply any needed facts in brief.", "unsupported_grounding", 422)
  }
  if (body.grounded !== false) throw new PublicError("Set grounded to false explicitly.", "invalid_request")
  if (body.locale !== undefined && (typeof body.locale !== "string" || body.locale.length > 64)) {
    throw new PublicError("locale must be a string of at most 64 characters.", "invalid_request")
  }
  const capabilities = body.capabilities ?? [
    { id: "nav", description: "Open a generated child screen", acceptsFormInput: true },
    { id: "send", description: "Send a follow-up to the host app", acceptsFormInput: true },
  ]
  if (!Array.isArray(capabilities) || capabilities.length === 0 || capabilities.length > 16
      || capabilities.some((cap) => !cap || !["nav", "send"].includes(cap.id)
        || typeof cap.description !== "string" || cap.description.length > 200)) {
    throw new PublicError("Provide nav and/or send capabilities. This backend does not resolve URL or custom actions.", "invalid_request")
  }
  const components = body.components ?? []
  if (!Array.isArray(components) || components.length > 32
      || components.some((component) => !supportedComponents.has(component))) {
    throw new PublicError("components must contain supported AuriUI component IDs.", "invalid_request")
  }
  return {
    brief: body.brief.trim(), grounded: false, locale: body.locale,
    components: [...new Set(components)],
    capabilities: capabilities.map((cap) => ({ ...cap, acceptsFormInput: cap.acceptsFormInput === true || cap.acceptsFormInput === "true" || cap.accepts_form_input === true })),
  }
}

function validatedDocument(text, body) {
  const lines = text.trim().split(/\r?\n/)
  const syntax = lines.map(unquotedAuiLine).join("\n")
  if (lines[0] !== "aui 1" || lines.filter((line) => /^aui\b/.test(line)).length !== 1
      || !/^screen [a-z][a-z0-9_]* "/.test(lines[1] ?? "")
      || lines.filter((line) => /^screen\b/.test(line)).length !== 1
      || /\b(?:img|url):|@url\s*\(|^(?:hero|posters|sources)\b/m.test(syntax)) {
    throw new PublicError("The generated screen used an unsupported version or resource service. Try again.", "invalid_screen")
  }
  const abilities = new Set(body.capabilities.map(({ id }) => id))
  if ([...syntax.matchAll(/@([a-z_]+)\s*\(/gi)].some((match) => !abilities.has(match[1]))) {
    throw new PublicError("The generated screen requested an unavailable action. Try again.", "invalid_screen")
  }
  const unsupportedKeywords = new Set(AUI_COMPONENTS
    .filter(({ id, requiresClientSupport }) => requiresClientSupport && !body.components.includes(id))
    .flatMap(({ keywords }) => keywords))
  if (syntax.split("\n").some((line) => unsupportedKeywords.has(line.split(/\s+/, 1)[0].toLowerCase()))) {
    throw new PublicError("The generated screen used a component this client does not support. Try again.", "invalid_screen")
  }
  const result = validateAuiText(text, body)
  if (!result.ok || result.dropped > 0) {
    throw new PublicError("The generated screen was incomplete or invalid. Try again.", "invalid_screen")
  }
  return result
}

// Pull-driven iteration preserves downstream backpressure. Both transport bytes
// and accumulated document text are capped before parsing or retaining more.
async function* completion(response, signal) {
  if (!response.ok || !response.body) {
    await response.body?.cancel()
    throw new PublicError(response.status === 429 ? "The generation provider is busy. Try again shortly." : "The generation provider could not complete the request.")
  }
  if (!response.headers.get("Content-Type")?.includes("text/event-stream")) {
    await response.body.cancel()
    throw new PublicError("The generation provider returned an unexpected response.")
  }
  const reader = response.body.getReader()
  const decoder = new TextDecoder("utf-8", { fatal: true })
  let buffer = ""
  let bytes = 0
  let finishReason = null
  const consume = function* (frame) {
    const data = frame.split("\n").filter((line) => line.startsWith("data:")).map((line) => line.slice(5).trimStart()).join("\n")
    if (!data) return
    if (data === "[DONE]") { yield { done: true }; return }
    let payload
    try { payload = JSON.parse(data) } catch { throw new PublicError("The generation stream contained invalid data.") }
    if (payload.error) throw new PublicError("The generation provider could not complete the request.")
    const choice = payload.choices?.[0]
    if (typeof choice?.finish_reason === "string") finishReason = choice.finish_reason
    if (typeof choice?.delta?.content === "string") yield { text: choice.delta.content }
  }
  try {
    let ended = false
    while (!ended) {
      const { value, done } = await read(reader, signal)
      if (done) {
        buffer += decoder.decode()
        if (buffer.trim()) for (const event of consume(buffer)) if (event.text) yield event.text
        break
      }
      bytes += value.byteLength
      if (bytes > LIMITS.upstream) throw new PublicError("The generation exceeded its response limit.", "truncated_screen")
      buffer += decoder.decode(value, { stream: true })
      // Normalize CRLF only after a whole pair arrives, including split chunks.
      buffer = buffer.replace(/\r\n/g, "\n")
      let end
      while ((end = buffer.indexOf("\n\n")) >= 0) {
        const frame = buffer.slice(0, end)
        if (encoder.encode(frame).byteLength > LIMITS.event) throw new PublicError("The generation event exceeded its limit.", "truncated_screen")
        buffer = buffer.slice(end + 2)
        for (const event of consume(frame)) {
          if (event.done) { ended = true; break }
          if (event.text) yield event.text
        }
        if (ended) break
      }
      if (encoder.encode(buffer).byteLength > LIMITS.event) throw new PublicError("The generation event exceeded its limit.", "truncated_screen")
    }
    if (finishReason !== "stop") {
      throw new PublicError(finishReason === "length" ? "The generated screen exceeded its token limit. Try a shorter brief." : "The generation stream ended before completion. Try again.", finishReason === "length" ? "truncated_screen" : "dropped_stream")
    }
  } finally {
    await reader.cancel().catch(() => {})
    reader.releaseLock()
  }
}

function event(name, data) { return encoder.encode(`event: ${name}\ndata: ${JSON.stringify(data)}\n\n`) }

async function* generate(body, env, signal, fetcher) {
  yield event("status", { phase: "designing" })
  try {
    const request = {
      model: env.CEREBRAS_MODEL, stream: true, max_completion_tokens: 3_000,
      messages: [
        { role: "system", content: buildAuiInstructions({ ...body, resourceMode: "none" }) },
        { role: "user", content: `Generate this screen using only supplied facts and stable common knowledge:\n${body.brief}` },
      ],
    }
    if (env.CEREBRAS_REASONING_EFFORT) request.reasoning_effort = env.CEREBRAS_REASONING_EFFORT
    const response = await fetcher(endpoint, {
      method: "POST", headers: { Authorization: `Bearer ${env.CEREBRAS_API_KEY}`, "Content-Type": "application/json" },
      body: JSON.stringify(request), signal,
    })
    let text = ""
    let bytes = 0
    for await (const delta of completion(response, signal)) {
      bytes += encoder.encode(delta).byteLength
      if (bytes > LIMITS.document) throw new PublicError("The generated screen exceeded its size limit.", "truncated_screen")
      text += delta
      yield event("aui.delta", { text: delta })
    }
    const document = validatedDocument(text, body)
    yield event("aui.document", { text: document.text, screen_id: document.screenId, sections: document.sections, dropped_lines: document.dropped })
    yield event("done", { outcome: "screen", grounded: false })
  } catch (error) {
    const failure = signal.aborted
      ? new PublicError("Generation timed out or was cancelled. Try again.", "timeout")
      : error instanceof PublicError ? error : new PublicError("The generation provider could not complete the request. Try again.")
    yield event("error", { message: failure.message })
    yield event("done", { outcome: failure.outcome })
  }
}

// fetcher injection is confined to tests; deployment always uses the fixed
// Cerebras HTTPS endpoint, never an endpoint supplied by a request.
export function createWorker(fetcher = fetch) {
  return {
    async fetch(request, env) {
      const path = new URL(request.url).pathname
      if (path === "/health" && request.method === "GET") {
        return json({ status: "ok", protocol: "aui 1", generation: "cerebras", grounding: false, images: false, url_lookup: false })
      }
      if (path !== "/screen") return json({ error: "Not found." }, 404)
      if (request.method !== "POST") return json({ error: "Use POST /screen." }, 405)
      if (!env.BACKEND_TOKEN || env.BACKEND_TOKEN.length < 32 || !env.CEREBRAS_API_KEY || !env.CEREBRAS_MODEL) {
        return json({ error: "Configure BACKEND_TOKEN (at least 32 characters), CEREBRAS_API_KEY, and CEREBRAS_MODEL on the Worker." }, 503)
      }
      if (!authorize(request, env)) return json({ error: "Unauthorized." }, 401)
      let body
      try { body = await requestBody(request) } catch (error) { return json({ error: error.message }, error.status ?? 400) }
      const abort = new AbortController()
      const signal = AbortSignal.any([request.signal, abort.signal, AbortSignal.timeout(LIMITS.timeout)])
      const iterator = generate(body, env, signal, fetcher)
      const stream = new ReadableStream({
        async pull(controller) {
          const { value, done } = await iterator.next()
          if (done) controller.close()
          else controller.enqueue(value)
        },
        async cancel() {
          abort.abort()
          await iterator.return()
        },
      }, { highWaterMark: 0 })
      return new Response(stream, { headers: { "Content-Type": "text/event-stream; charset=utf-8", "Cache-Control": "no-cache, no-store", "X-Content-Type-Options": "nosniff" } })
    },
  }
}

export default createWorker()
