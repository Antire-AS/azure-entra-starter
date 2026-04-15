import os

from fastapi import FastAPI, Request, HTTPException
from fastapi.responses import StreamingResponse, RedirectResponse
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


# --- Public routes (no auth required) ---
# These work regardless of Easy Auth mode. With AllowAnonymous, they are
# accessible without signing in. With RedirectToLoginPage (default), all
# requests are already authenticated before reaching your app.


@app.get("/health")
async def health():
    return {"status": "ok"}


# --- Auth helpers for selective route protection ---
# When Easy Auth is set to AllowAnonymous, your app receives ALL requests —
# both authenticated and anonymous. Authenticated requests have identity
# headers injected by the Easy Auth proxy. Anonymous requests have no headers.
#
# Use these helpers to protect specific routes while leaving others public.
# If Easy Auth is set to RedirectToLoginPage (default), these checks always
# pass because the proxy already blocked unauthenticated requests.


def get_user_email(request: Request) -> str | None:
    """Get the authenticated user's email from Easy Auth headers, or None."""
    return request.headers.get("X-MS-CLIENT-PRINCIPAL-NAME")


def require_auth(request: Request) -> str:
    """Require authentication. Returns user email or redirects to login.

    For browser requests (Accept: text/html), redirects to /.auth/login/aad.
    For API requests, returns 401.
    """
    email = get_user_email(request)
    if email:
        return email

    if "text/html" in request.headers.get("accept", ""):
        raise HTTPException(
            status_code=303,
            headers={"Location": "/.auth/login/aad?post_login_redirect_uri=" + str(request.url.path)},
        )
    raise HTTPException(status_code=401, detail="Not authenticated")


# --- Protected routes (auth required) ---
# These routes check for Easy Auth identity headers. With AllowAnonymous,
# unauthenticated users are redirected to Microsoft login. With
# RedirectToLoginPage, the check always passes (users are already signed in).


@app.get("/api/me")
async def get_current_user(request: Request):
    name = get_user_email(request) or ""
    return {"name": name}


@app.post("/api/chat")
async def chat(request: Request):
    # Require auth for chat — unauthenticated users get redirected/401
    require_auth(request)

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
