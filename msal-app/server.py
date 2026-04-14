import os
import time

import httpx
import jwt
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, StreamingResponse
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

# Entra ID configuration — set by Terraform or environment variables.
TENANT_ID = os.environ["AZURE_TENANT_ID"]
CLIENT_ID = os.environ["AZURE_CLIENT_ID"]

# The OpenID Connect discovery URL for your tenant.
OPENID_CONFIG_URL = (
    f"https://login.microsoftonline.com/{TENANT_ID}/v2.0/.well-known/openid-configuration"
)

# --- JWKS Cache ---
# Microsoft's signing keys rotate periodically. We cache the JWKS (JSON Web Key Set)
# to avoid fetching it on every request. The cache is refreshed every 24 hours or
# when token validation fails with a key-not-found error (which means Microsoft
# rotated keys and our cache is stale).

_jwks_cache: dict = {}
_jwks_fetched_at: float = 0
JWKS_CACHE_SECONDS = 86400  # 24 hours


def _fetch_jwks() -> dict:
    """Fetch the JWKS from Microsoft's OpenID Connect discovery endpoint."""
    global _jwks_cache, _jwks_fetched_at

    # Step 1: Get the JWKS URI from the OpenID Connect discovery document.
    config = httpx.get(OPENID_CONFIG_URL).json()
    jwks_uri = config["jwks_uri"]

    # Step 2: Fetch the actual signing keys.
    jwks = httpx.get(jwks_uri).json()

    _jwks_cache = jwks
    _jwks_fetched_at = time.time()
    return jwks


def _get_jwks() -> dict:
    """Get the JWKS, using cache when possible."""
    if _jwks_cache and (time.time() - _jwks_fetched_at) < JWKS_CACHE_SECONDS:
        return _jwks_cache
    return _fetch_jwks()


def validate_token(token: str) -> dict:
    """
    Validate a JWT ID token from Entra ID.

    Checks:
      - Signature: verified against Microsoft's published signing keys (JWKS)
      - Audience (aud): must match our app's client ID
      - Issuer (iss): must be our Entra ID tenant
      - Expiry (exp): token must not be expired

    Returns the decoded token claims if valid.
    Raises jwt.PyJWTError if validation fails.
    """
    jwks = _get_jwks()

    # Get the key ID from the token header — this tells us which signing key to use.
    header = jwt.get_unverified_header(token)
    kid = header.get("kid")

    # Find the matching key in the JWKS.
    signing_key = None
    for key in jwks.get("keys", []):
        if key["kid"] == kid:
            signing_key = jwt.algorithms.RSAAlgorithm.from_jwk(key)
            break

    if signing_key is None:
        # Key not found — Microsoft may have rotated keys. Refresh the cache and retry.
        jwks = _fetch_jwks()
        for key in jwks.get("keys", []):
            if key["kid"] == kid:
                signing_key = jwt.algorithms.RSAAlgorithm.from_jwk(key)
                break

    if signing_key is None:
        raise jwt.InvalidTokenError(f"Signing key {kid} not found in JWKS")

    # Validate and decode the token.
    claims = jwt.decode(
        token,
        key=signing_key,
        algorithms=["RS256"],
        audience=CLIENT_ID,
        issuer=f"https://login.microsoftonline.com/{TENANT_ID}/v2.0",
    )
    return claims


@app.get("/health")
async def health():
    return {"status": "ok"}


@app.get("/api/me")
async def get_current_user(request: Request):
    auth_header = request.headers.get("Authorization", "")
    if not auth_header.startswith("Bearer "):
        return JSONResponse({"error": "Not authenticated"}, status_code=401)

    try:
        claims = validate_token(auth_header[7:])
        return {"name": claims.get("preferred_username", claims.get("email", ""))}
    except jwt.PyJWTError:
        return JSONResponse({"error": "Invalid token"}, status_code=401)


@app.post("/api/chat")
async def chat(request: Request):
    # Validate the Bearer token before processing the request.
    auth_header = request.headers.get("Authorization", "")
    if not auth_header.startswith("Bearer "):
        return JSONResponse({"error": "Not authenticated"}, status_code=401)

    try:
        validate_token(auth_header[7:])
    except jwt.PyJWTError:
        return JSONResponse({"error": "Invalid token"}, status_code=401)

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
