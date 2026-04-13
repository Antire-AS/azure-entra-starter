const { app } = require("@azure/functions");
const OpenAI = require("openai");

// Note: Azure Static Web Apps buffers function responses before forwarding
// them to the client. This means streaming (SSE, chunked responses) does not
// work when deployed — the client receives the entire response at once.
// This is a known SWA limitation (github.com/Azure/static-web-apps/issues/1180).
// If you need streaming, use the Container App option instead.

app.http("chat", {
  methods: ["POST"],
  authLevel: "anonymous",
  route: "chat",
  handler: async (request) => {
    const { messages } = await request.json();

    const client = new OpenAI({
      apiKey: process.env.AZURE_OPENAI_API_KEY,
      baseURL: `${process.env.AZURE_OPENAI_ENDPOINT}/openai/deployments/${process.env.AZURE_OPENAI_DEPLOYMENT}`,
      defaultQuery: { "api-version": "2024-08-01-preview" },
      defaultHeaders: { "api-key": process.env.AZURE_OPENAI_API_KEY },
    });

    const systemPrompt =
      process.env.SYSTEM_PROMPT || "You are a helpful assistant.";

    const completion = await client.chat.completions.create({
      model: process.env.AZURE_OPENAI_DEPLOYMENT,
      messages: [{ role: "system", content: systemPrompt }, ...messages],
    });

    return {
      body: completion.choices[0].message.content,
      headers: { "Content-Type": "text/plain" },
    };
  },
});
