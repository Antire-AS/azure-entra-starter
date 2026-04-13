import os

from fastapi import FastAPI, Request
from fastapi.responses import StreamingResponse
from fastapi.staticfiles import StaticFiles
from openai import AzureOpenAI

app = FastAPI()

client = AzureOpenAI(
    api_key=os.environ["AZURE_OPENAI_API_KEY"],
    api_version="2024-08-01-preview",
    azure_endpoint=os.environ["AZURE_OPENAI_ENDPOINT"],
)

DEPLOYMENT = os.environ.get("AZURE_OPENAI_DEPLOYMENT", "gpt-4o")
SYSTEM_PROMPT = os.environ.get("SYSTEM_PROMPT", "You are a helpful assistant.")


@app.get("/health")
async def health():
    return {"status": "ok"}


@app.get("/api/me")
async def get_current_user(request: Request):
    name = request.headers.get("X-MS-CLIENT-PRINCIPAL-NAME", "")
    return {"name": name}


@app.post("/api/chat")
async def chat(request: Request):
    body = await request.json()
    messages = body.get("messages", [])

    def stream():
        response = client.chat.completions.create(
            model=DEPLOYMENT,
            messages=[{"role": "system", "content": SYSTEM_PROMPT}] + messages,
            stream=True,
        )
        for chunk in response:
            if chunk.choices and chunk.choices[0].delta.content:
                yield chunk.choices[0].delta.content

    return StreamingResponse(stream(), media_type="text/plain")


app.mount("/", StaticFiles(directory="static", html=True), name="static")
