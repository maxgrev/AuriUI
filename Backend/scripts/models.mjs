// Reads only the developer's ignored local environment and prints model IDs.
// Never print the API key or an upstream error body.
if (!process.env.CEREBRAS_API_KEY) {
  console.error("Set CEREBRAS_API_KEY in .dev.vars first.")
  process.exitCode = 1
} else {
  try {
    const response = await fetch("https://api.cerebras.ai/v1/models", {
      headers: { Authorization: `Bearer ${process.env.CEREBRAS_API_KEY}` },
      signal: AbortSignal.timeout(10_000),
    })
    if (!response.ok) throw new Error(`Cerebras returned HTTP ${response.status}. Check your key and account access.`)
    const reader = response.body.getReader()
    let size = 0
    const chunks = []
    try {
      while (true) {
        const { done, value } = await reader.read()
        if (done) break
        size += value.byteLength
        if (size > 1_048_576) throw new Error("Cerebras returned an oversized model list.")
        chunks.push(value)
      }
      const result = JSON.parse(Buffer.concat(chunks).toString("utf8"))
      const models = result.data?.map(({ id }) => id).filter((id) => typeof id === "string")
      if (!models?.length) throw new Error("No models are available for this account.")
      console.log(models.join("\n"))
    } finally {
      await reader.cancel()
    }
  } catch (error) {
    console.error(error instanceof Error && error.message.startsWith("Cerebras returned") ? error.message : "Could not list models. Check your connection and Cerebras account.")
    process.exitCode = 1
  }
}
