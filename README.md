# Azure Entra Starter

Starter template for Azure-hosted apps protected by Entra ID (Azure AD) authentication. Includes a working chat interface as the example app, Terraform infrastructure, and two different auth approaches: Easy Auth (platform-managed) and MSAL (client-side).

Pick one of three deployment options:

### Option A: Static Web App

For teams that want the simplest possible setup. No Docker, no servers — Azure hosts your frontend as static files and runs your backend as Azure Functions. Everything deploys with the SWA CLI. The backend is Node.js.

Limitation: the SWA reverse proxy buffers API responses, so streaming (token-by-token chat) does not work when deployed. The chat response arrives all at once. This is a [known SWA limitation](https://github.com/Azure/static-web-apps/issues/1180). If streaming matters, use the Container App option.

Best for: internal tools, dashboards, lightweight apps where you want to go from zero to deployed in minutes. Fixed cost (~$9/mo for the Standard plan needed for Entra ID auth).

### Option B: Container App

For teams that need more control. You package your app in a Docker container and Azure runs it. The backend is Python (FastAPI). Scales to zero when idle (no traffic = no cost). Supports agent/service access via client credentials.

Best for: apps with heavier backend logic, teams already using Docker, projects that need service-to-service API access, or apps that may grow beyond what static hosting supports.

### Option C: MSAL App (client-side auth)

For teams that want full control over the authentication flow. Instead of relying on Azure's built-in Easy Auth proxy, your frontend handles login using Microsoft's MSAL.js library and your backend validates tokens directly. Same Docker-based hosting as Option B, but authentication lives in your code, not in Azure infrastructure.

Best for: apps that may run outside Azure, teams that want to customize the login experience, SPAs that need fine-grained token control, or projects where you want to understand exactly what the auth code does.

### Comparison

|                          | Static Web App              | Container App                  | MSAL App                        |
|--------------------------|-----------------------------|--------------------------------|---------------------------------|
| **Hosting**              | Azure Static Web Apps       | Azure Container Apps           | Azure Container Apps            |
| **Backend**              | Azure Functions (Node.js)   | FastAPI (Python)               | FastAPI (Python)                |
| **Auth**                 | Easy Auth (platform)        | Easy Auth (platform)           | MSAL.js (client-side)           |
| **Auth code in your app**| None                        | None                           | Yes (frontend + backend)        |
| **Streaming responses**  | No (SWA proxy buffers)      | Yes                            | Yes                             |
| **Cost**                 | ~$9/mo (Standard plan)      | Pay-per-use (scales to zero)   | Pay-per-use (scales to zero)    |
| **Docker**               | Not needed                  | Required                       | Required                        |
| **Portable (non-Azure)** | No (Azure-only feature)     | No (Azure-only feature)        | Yes (auth runs in your code)    |
| **Agent/service access** | Not supported               | Yes (client credentials flow)  | Yes (client credentials flow)   |

Options A and B use the same frontend, the same Entra ID Easy Auth pattern, and the same approach to group-based access control. Option C uses the same chat UI but handles auth in application code instead of the platform. Each has its own self-contained Terraform — no shared modules, easy to read.

---

## Understanding Easy Auth

### The problem

You have a web app and you want only people in your organization to access it. The traditional approach is to write authentication code yourself: redirect users to Microsoft login, handle the OAuth callback, validate tokens, manage sessions, refresh expired tokens, handle edge cases. That's a lot of security-critical code to get right.

### What Easy Auth does

Easy Auth is Azure's built-in authentication. Instead of writing auth code, you tell Azure: "protect this app with Entra ID." Azure places a reverse proxy in front of your app that handles the entire login flow. Your application code doesn't know authentication exists — it just receives requests that are already authenticated.

This is not a library or an SDK you install. It's an infrastructure-level feature that runs outside your application, managed by Azure.

### What happens when a user visits your app

```
1. First visit (not logged in)

   Browser ──── GET / ────> Azure Easy Auth proxy ─────> (blocked)
                                    │
                                    ├─ No auth cookie found
                                    ├─ Redirect browser to Microsoft login
                                    │
   Browser <── 302 ────────────────┘
   Browser ──── Opens login.microsoftonline.com
   User enters their organization credentials


2. After signing in

   Microsoft ── redirects back to ──> Azure Easy Auth proxy
                                           │
                                           ├─ Receives auth token from Microsoft
                                           ├─ Validates the token
                                           ├─ Creates a session cookie
                                           ├─ Stores the cookie in the browser
                                           │
   Browser <── 302 redirect to app ───────┘


3. Every subsequent request

   Browser ──── GET / (with cookie) ────> Azure Easy Auth proxy ────> Your app
                                                │                        │
                                                ├─ Cookie valid          │
                                                ├─ Injects HTTP headers: │
                                                │  X-MS-CLIENT-PRINCIPAL-NAME: user@company.com
                                                │  x-ms-client-principal: (base64 JSON with claims)
                                                │                        │
                                                └────────────────────────┘

   Your app sees the request with the user's identity in the headers.
   It never saw the login page. It never validated a token. It just reads a header.
```

### What your app code actually does

Almost nothing. Here is the entire auth-related code in the Container App backend:

```python
@app.get("/api/me")
async def get_current_user(request: Request):
    name = request.headers.get("X-MS-CLIENT-PRINCIPAL-NAME", "")
    return {"name": name}
```

That's it. One header read. Easy Auth handles everything else.

The frontend is equally simple — it calls `/.auth/me` (a built-in endpoint provided by Easy Auth, not your code) to get the user's email for display:

```javascript
const res = await fetch('/.auth/me');
const data = await res.json();
// data.clientPrincipal.userDetails = "user@company.com"
```

### Built-in endpoints

Easy Auth provides these endpoints automatically on both Static Web Apps and Container Apps. You don't create them — they exist the moment Easy Auth is enabled:

| Endpoint | What it does |
|----------|-------------|
| `/.auth/login/aad` | Starts the Microsoft login flow |
| `/.auth/login/aad/callback` | Handles the redirect back from Microsoft after login |
| `/.auth/me` | Returns the current user's identity (email, user ID, roles) |
| `/.auth/logout` | Signs the user out and clears the session |

The frontend uses `/.auth/me` to show the username and links to `/.auth/logout` for the sign-out button. That's the only interaction your code has with the auth system.

---

## Understanding MSAL

### Why MSAL instead of Easy Auth?

Easy Auth is convenient — zero auth code, the platform handles everything. But it only works on Azure, you can't customize the login experience, and you can't see or control what happens during authentication.

MSAL (Microsoft Authentication Library) is the alternative: your application handles auth directly. The frontend acquires tokens using Microsoft's JavaScript library, and your backend validates them. More code, but also:

- **Portable**: your app can run anywhere (Azure, AWS, on-prem, localhost) — auth doesn't depend on Azure's reverse proxy.
- **Visible**: you can see every step of the auth flow, debug it, and customize it.
- **Fine-grained**: you control token scopes, caching, refresh behavior, and error handling.
- **Testable**: you can test auth logic locally without deploying to Azure.

### What MSAL does

MSAL.js is a JavaScript library that runs in the browser. It handles the OAuth 2.0 authorization code flow with PKCE: redirecting users to Microsoft's login page, receiving the authorization code, exchanging it for tokens, caching them, and silently refreshing them when they expire.

This is not a proxy or infrastructure feature. It's a library loaded in your HTML page, like jQuery or Alpine.js. Your backend receives the token in the `Authorization` header and validates it against Microsoft's published signing keys.

### What happens when a user visits your app

```
1. First visit (not logged in)

   Browser ──── GET / ────> Your backend ──── serves index.html
                                                   │
   Browser runs JavaScript:                        │
     MSAL checks sessionStorage — no cached account│
     App shows "Sign in with Microsoft" button      │
                                                   │
   User clicks the button                          │
     MSAL redirects to login.microsoftonline.com   │
     User enters their organization credentials    │


2. After signing in

   Microsoft ── redirects back to ──> Your app's origin URL
                                           │
   Browser runs JavaScript:                │
     MSAL's handleRedirectPromise() runs   │
     Receives the authorization code       │
     Exchanges it for tokens via PKCE      │
     Stores tokens in sessionStorage       │
     App renders the chat interface        │


3. Every subsequent API call

   Browser ──── POST /api/chat ────> Your backend
                    │                      │
                    │ Authorization:        │
                    │ Bearer eyJ0eX...      │
                    │                      │
                    │                Your backend:
                    │                  1. Extracts the token from the header
                    │                  2. Fetches Microsoft's signing keys (JWKS)
                    │                  3. Verifies the token signature
                    │                  4. Checks audience = your app's client ID
                    │                  5. Checks issuer = your Entra ID tenant
                    │                  6. Checks the token is not expired
                    │                  7. If valid → processes the request
                    │                  8. If invalid → returns 401
                    │
   Your backend never redirects to a login page. It never issues tokens.
   It only validates tokens that the frontend already acquired.
```

### What your app code actually does

**Frontend** — MSAL handles the login flow. Your code initializes it, calls login, and attaches the token to API requests:

```javascript
// Initialize MSAL with your app's client ID and tenant ID
const msalInstance = new msal.PublicClientApplication({
    auth: {
        clientId: 'your-client-id',
        authority: 'https://login.microsoftonline.com/your-tenant-id',
        redirectUri: window.location.origin,
    },
    cache: { cacheLocation: 'sessionStorage' },
});

// On page load: handle the redirect callback (if returning from Microsoft login)
const response = await msalInstance.handleRedirectPromise();

// Login: redirect the browser to Microsoft's login page
await msalInstance.loginRedirect({ scopes: ['User.Read'] });

// Get a token for API calls (uses cache, refreshes silently if expired)
const tokenResponse = await msalInstance.acquireTokenSilent({
    scopes: ['User.Read'],
    account: msalInstance.getAllAccounts()[0],
});

// Send the token with every API call
fetch('/api/chat', {
    headers: { 'Authorization': `Bearer ${tokenResponse.idToken}` },
    // ...
});
```

**Backend** — validates the JWT token on every request. No MSAL library needed on the server — just standard JWT validation:

```python
import jwt, httpx

# Fetch Microsoft's signing keys (cached, refreshed daily)
jwks = httpx.get("https://login.microsoftonline.com/{tenant}/discovery/v2.0/keys").json()

# Validate the token from the Authorization header
claims = jwt.decode(
    token,
    key=signing_key,          # from the JWKS, matched by key ID
    algorithms=["RS256"],
    audience="your-client-id",
    issuer="https://login.microsoftonline.com/{tenant}/v2.0",
)
user_email = claims["preferred_username"]
```

Compare this with Easy Auth, where the entire auth code is `request.headers.get("X-MS-CLIENT-PRINCIPAL-NAME")`. MSAL requires more code, but every step is explicit and under your control.

### Tokens: ID tokens vs access tokens

Microsoft issues two types of tokens. Understanding the difference matters for MSAL apps:

| | ID Token | Access Token |
|---|---|---|
| **Purpose** | Identifies who the user is | Authorizes access to a specific API |
| **Contains** | User's email, name, tenant ID | Scopes (permissions) for a target API |
| **Audience (aud)** | Your app's client ID | The API's resource URI |
| **Used for** | Authenticating to your own backend | Calling Microsoft Graph or other APIs |
| **Example** | "This is alice@company.com" | "alice has User.Read permission on Graph" |

In this starter, the frontend sends the **ID token** to your backend. The backend validates that the token is signed by Microsoft, intended for your app, and not expired. That's enough to know who the user is.

Access tokens are used when calling external APIs (like Microsoft Graph to check group membership). The frontend uses them internally — your backend never sees them.

### When to use MSAL vs Easy Auth

| Scenario | Recommendation |
|----------|---------------|
| Internal tool, deployed to Azure, minimal auth requirements | **Easy Auth** — zero code, platform handles it |
| Need auth to work locally during development | **MSAL** — Easy Auth only works when deployed |
| App may run outside Azure (AWS, on-prem, Docker locally) | **MSAL** — not tied to Azure infrastructure |
| Need to customize the login page or flow | **MSAL** — full control over the UI |
| Want to understand exactly how auth works | **MSAL** — every step is in your code |
| Need to call Microsoft Graph from the frontend | **MSAL** — already has the access tokens |
| Want the least amount of code possible | **Easy Auth** — literally one header read |

---

## What is an App Registration?

Before Easy Auth can work, Microsoft needs to know your app exists. An **app registration** is your app's identity in Entra ID — it tells Microsoft "there is an application called X, and it's allowed to use Microsoft login."

The Terraform in this repo creates the app registration automatically. Here's what it configures:

| Setting | Value | What it means |
|---------|-------|---------------|
| `sign_in_audience` | `AzureADMyOrg` | Only people in your organization can sign in. No personal Microsoft accounts, no other tenants. |
| `redirect_uris` | `https://<your-app>/.auth/login/aad/callback` | After login, Microsoft redirects the user back to this URL. Easy Auth handles the callback. |
| `id_token_issuance_enabled` | `true` | Microsoft will issue ID tokens that identify the user. |

You generally don't need to touch the app registration after Terraform creates it. The one manual step is that an Entra ID admin must add the deploying user as **Owner** of the registration — this is a one-time action documented in the deployment steps.

### App registration differences: Easy Auth vs MSAL

The Terraform creates the app registration for you, but the configuration differs:

| Setting | Easy Auth (Options A/B) | MSAL (Option C) |
|---------|------------------------|-----------------|
| Platform type | Web | Single Page Application (SPA) |
| Redirect URI type | Web (`/.auth/login/aad/callback`) | SPA (app origin URL) |
| Client secret | Needed for SWA, not for Container App | Not needed (uses PKCE) |
| Implicit grant | ID tokens enabled | ID tokens enabled |
| PKCE | Handled by Easy Auth internally | Handled by MSAL.js in the browser |

The SPA platform type tells Entra ID to accept PKCE-based token requests from the browser. No client secret is exchanged — the browser can't keep secrets, so PKCE uses a dynamically generated challenge instead.

---

## How Easy Auth works on each platform

Both options use Easy Auth, but the implementation details differ slightly.

### On Container Apps

Easy Auth runs as a **sidecar proxy** next to your container. Every HTTP request passes through it before reaching your application. The Terraform configures this using `azapi_resource` (which calls the Azure REST API directly to set up the auth proxy).

```
Internet ──> Container Apps ingress ──> Easy Auth sidecar ──> Your container (port 8000)
                                             │
                                             ├─ Validates session cookie
                                             ├─ Injects X-MS-CLIENT-PRINCIPAL-NAME header
                                             ├─ Unauthenticated? Redirect to Microsoft login
                                             └─ No client secret needed (implicit flow)
```

Key details:
- Configured in `terraform/container-app/auth.tf`
- No client secret required — uses implicit grant (ID tokens only)
- Your backend reads `X-MS-CLIENT-PRINCIPAL-NAME` header to get the user's email
- The `/.auth/me` endpoint returns an array of identity objects

### On Static Web Apps

Easy Auth is **built into the platform edge** — there's no separate proxy to configure. You control it with a JSON config file (`staticwebapp.config.json`) that lives in your repository.

```
Internet ──> Static Web Apps edge ──> Your frontend (static files)
                    │                      │
                    ├─ Reads staticwebapp.config.json
                    ├─ Checks route rules + allowedRoles
                    ├─ Validates session cookie
                    ├─ Passes x-ms-client-principal header to API functions
                    ├─ Unauthenticated? Redirect to Microsoft login
                    └─ Client secret required (set as app setting)
```

Key details:
- Configured in `frontend/staticwebapp.config.json` (auth provider) and Terraform (app settings with client ID/secret)
- Client secret is required — SWA uses authorization code flow
- Your API functions read the `x-ms-client-principal` header (base64-encoded JSON)
- The `/.auth/me` endpoint returns a `clientPrincipal` object
- Route-level access control: each route specifies `allowedRoles`

### The difference in practice

From your app's perspective, the experience is identical. Users log in with Microsoft, your code reads a header to know who they are. The differences are infrastructure-level:

| | Container App | Static Web App |
|---|---|---|
| Where auth runs | Sidecar proxy next to your container | Built into the platform edge |
| How it's configured | Terraform `azapi_resource` | `staticwebapp.config.json` + Terraform app settings |
| Client secret | Not needed | Required |
| Route-level auth rules | All-or-nothing (all routes protected) | Per-route via `allowedRoles` in config |
| User info header | `X-MS-CLIENT-PRINCIPAL-NAME` (plain text) | `x-ms-client-principal` (base64 JSON) |

---

## Managing access — who can use the app

### The three levels of access control

There are three levels that determine whether someone can reach your app. Each level narrows the audience further:

```
Level 1: Entra ID tenant
    Everyone in your organization has an Entra ID account.
    With sign_in_audience = "AzureADMyOrg", only these people can sign in.
    External users and personal Microsoft accounts are blocked.
         │
         ▼
Level 2: Security group (optional)
    You can create a security group (e.g. "Chat App Users") and
    restrict the app so only group members can access it.
    Everyone else in the org gets a "not authorized" page.
         │
         ▼
Level 3: Roles within the app (optional)
    Within the allowed users, you can assign different roles
    (e.g. "admin", "chat-user") to control what they can do.
    Different routes or features can require different roles.
```

Out of the box, this starter uses **Level 1 only** — anyone in your organization can sign in. Levels 2 and 3 are opt-in.

### Level 1: Tenant-wide access (default)

This is what you get with no extra configuration. The app registration is set to `AzureADMyOrg`, which means any user in your Entra ID tenant can log in.

**Who is in your tenant?** Everyone with an `@yourcompany.com` account managed by your IT department. You can see all users in the Azure portal:

```
Portal: Entra ID -> Users -> All users
```

**Adding external users (guests):** If you need someone outside your organization to access the app, an admin can invite them as a guest user:

```
Portal: Entra ID -> Users -> New user -> Invite external user

    Enter their email address
    They receive an invitation email
    After accepting, they appear in your tenant as a guest
    They can now sign in to the app
```

Or via CLI:
```bash
az ad user create --display-name "Guest Name" \
  --user-principal-name "guest@yourcompany.com" \
  --password "TempPassword123!"

# Or invite an external user
az rest --method POST \
  --url "https://graph.microsoft.com/v1.0/invitations" \
  --body '{"invitedUserEmailAddress":"user@external.com","inviteRedirectUrl":"https://your-app.azurestaticapps.net"}'
```

### Level 2: Restricting access to a security group

If you don't want the entire organization to have access, create a security group and restrict the app to its members.

#### Step 1: Create a security group

```
Portal: Entra ID -> Groups -> New group

    Group type:     Security
    Group name:     Chat App Users
    Description:    Users allowed to access the chat application
    Membership type: Assigned (you manually add members)

    Click "Create"
```

Or via CLI:
```bash
az ad group create --display-name "Chat App Users" \
  --mail-nickname "chat-app-users" \
  --description "Users allowed to access the chat application"
```

#### Step 2: Add members to the group

```
Portal: Entra ID -> Groups -> Chat App Users -> Members -> Add members

    Search for users by name or email
    Select one or more users
    Click "Select"
```

Or via CLI:
```bash
# Get the group ID
GROUP_ID=$(az ad group show --group "Chat App Users" --query id -o tsv)

# Add a user by email
USER_ID=$(az ad user show --id "user@yourcompany.com" --query id -o tsv)
az ad group member add --group $GROUP_ID --member-id $USER_ID
```

#### Step 3: Connect the group to your app

All three options work the same way. Add the group to your Terraform apply:

```bash
terraform apply \
  -var="create_access_group=true" \
  -var="access_group_name=Chat App Users" \
  -var='access_group_members=["alice@company.com", "bob@company.com"]' \
  ...other vars...
```

Or if you already have a group, Terraform can create it without initial members — you add people via the portal later.

This does three things:
1. Creates a security group in Entra ID
2. Sets `app_role_assignment_required = true` on the service principal — telling Entra ID to only issue tokens to assigned users
3. Assigns the group to the app — telling Entra ID that group members are allowed

Non-members who try to sign in see error AADSTS50105 on Microsoft's login page and never reach your app. No middleware, no backend code — Entra ID handles it.

### Common access management tasks

| Task | How |
|------|-----|
| See who has access | Portal: Entra ID -> Groups -> [your group] -> Members |
| Add a user | Portal: Groups -> [your group] -> Members -> Add members |
| Remove a user | Portal: Groups -> [your group] -> Members -> select user -> Remove |
| Add someone outside the org | Portal: Entra ID -> Users -> Invite external user |
| See who signed in recently | Portal: Entra ID -> Sign-in logs (filter by app name) |
| Create a new group | Portal: Entra ID -> Groups -> New group (type: Security) |
| Find a group's Object ID | Portal: Groups -> [your group] -> Overview -> Object Id |

---

## Prerequisites

- Azure subscription with `az login` configured
- Terraform >= 1.0
- An Azure OpenAI resource (endpoint + API key + deployment name)
- A pre-existing Azure resource group
- An Entra ID admin who can grant app registration ownership (one-time setup)

---

## Option A: Static Web App

### 1. Deploy infrastructure

```bash
cd terraform/static-web-app
terraform init
terraform apply \
  -var="resource_group_name=rg-my-chat" \
  -var="project_name=my-chat" \
  -var="azure_openai_api_key=YOUR_KEY" \
  -var="azure_openai_endpoint=https://YOUR_RESOURCE.openai.azure.com" \
  -var="azure_openai_deployment=gpt-4o"
```

### 2. Update tenant ID

Replace `<TENANT_ID>` in `frontend/staticwebapp.config.json` with the `tenant_id` from terraform output.

### 3. Deploy the app

```bash
npm install -g @azure/static-web-apps-cli
cd api && npm install && cd ..
swa deploy --app-location frontend --api-location api \
  --deployment-token $(terraform -chdir=terraform/static-web-app output -raw api_key)
```

### Group access control (optional)

Restrict access to a specific Entra ID security group:

1. Add `-var="create_access_group=true"` to `terraform apply`
2. Optionally pass `-var='access_group_members=["user@company.com"]'` to seed the group
3. Non-members are blocked at the Microsoft login page (AADSTS50105)

---

## Option B: Container App

Deployment happens in two passes. The first creates the registry and Key Vault (no Docker image needed yet). The second creates the Container App after the image is pushed.

### 1. First pass — create registry and Key Vault

```bash
cd terraform/container-app
terraform init
terraform apply -target=azurerm_container_registry.main -target=azurerm_key_vault.main \
  -target=azurerm_role_assignment.kv_admin -target=azurerm_log_analytics_workspace.main \
  -var="resource_group_name=rg-my-chat" \
  -var="project_name=my-chat" \
  -var="azure_openai_endpoint=https://YOUR_RESOURCE.openai.azure.com" \
  -var="azure_openai_deployment=gpt-4o"
```

### 2. Store the API key

```bash
az keyvault secret set \
  --vault-name $(terraform output -raw key_vault_name) \
  --name azure-openai-api-key \
  --value YOUR_KEY
```

### 3. Build and push the Docker image

```bash
REGISTRY=$(terraform output -raw container_registry)
PROJECT=my-chat

# From the repo root
docker build --platform linux/amd64 -f container-app/Dockerfile -t $REGISTRY/$PROJECT:latest .
az acr login --name ${REGISTRY%%.*}
docker push $REGISTRY/$PROJECT:latest
```

### 4. Second pass — create Container App and Easy Auth

Now that the image exists in the registry, run the full apply:

```bash
terraform apply \
  -var="resource_group_name=rg-my-chat" \
  -var="project_name=my-chat" \
  -var="azure_openai_endpoint=https://YOUR_RESOURCE.openai.azure.com" \
  -var="azure_openai_deployment=gpt-4o"
```

### 5. Entra ID admin action

An Entra ID admin must add the deploying user as Owner of the app registration:

Portal -> Entra ID -> App registrations -> my-chat-dev -> Owners -> Add owner

Then re-run `terraform apply` to set the redirect URI.

### Agent/service access (optional, Container App only)

If you have an AI agent, a backend service, or any automated process that needs to call the chat API programmatically (no browser), it needs its own identity.

Add `-var="create_agent_identity=true"` to your `terraform apply`. This creates:
- An app registration for the agent (its own client ID + secret)
- An "Agent.Access" role on the chat app
- A role assignment connecting the two

After apply, get the agent's credentials:

```bash
terraform output agent_client_id
terraform output -raw agent_client_secret
terraform output agent_token_scope
terraform output agent_token_endpoint
```

The agent acquires a token and calls the API:

```python
import requests

# Step 1: Get a token (no browser, no human)
token_response = requests.post(
    "https://login.microsoftonline.com/<tenant>/oauth2/v2.0/token",
    data={
        "client_id": "<agent-client-id>",
        "client_secret": "<agent-secret>",
        "scope": "api://<chat-app-client-id>/.default",
        "grant_type": "client_credentials",
    },
)
token = token_response.json()["access_token"]

# Step 2: Call the chat API with the token
response = requests.post(
    "https://<your-app>/api/chat",
    headers={"Authorization": f"Bearer {token}"},
    json={"messages": [{"role": "user", "content": "Hello"}]},
)
print(response.text)
```

Easy Auth validates the Bearer token — same reverse proxy that protects browser access. The agent never sees a login page. See `terraform/container-app/agents.tf` for full documentation, including how to use managed identities instead of client secrets.

Note: This only works with the Container App option. Static Web Apps Easy Auth does not support Bearer token validation for service-to-service calls.

---

## Option C: MSAL App

Deployment is the same two-pass approach as Option B (registry + Key Vault first, then the Container App). The difference is that there's no Easy Auth configuration — your code handles auth.

### 1. First pass — create registry and Key Vault

```bash
cd terraform/msal-app
terraform init
terraform apply -target=azurerm_container_registry.main -target=azurerm_key_vault.main \
  -target=azurerm_role_assignment.kv_admin -target=azurerm_log_analytics_workspace.main \
  -var="resource_group_name=rg-my-chat" \
  -var="project_name=my-chat" \
  -var="azure_openai_endpoint=https://YOUR_RESOURCE.openai.azure.com" \
  -var="azure_openai_deployment=gpt-4o"
```

### 2. Store the API key

```bash
az keyvault secret set \
  --vault-name $(terraform output -raw key_vault_name) \
  --name azure-openai-api-key \
  --value YOUR_KEY
```

### 3. Build and push the Docker image

```bash
REGISTRY=$(terraform output -raw container_registry)
PROJECT=my-chat

# From the repo root
docker build --platform linux/amd64 -f msal-app/Dockerfile -t $REGISTRY/$PROJECT:latest .
az acr login --name ${REGISTRY%%.*}
docker push $REGISTRY/$PROJECT:latest
```

### 4. Second pass — create Container App and app registration

```bash
terraform apply \
  -var="resource_group_name=rg-my-chat" \
  -var="project_name=my-chat" \
  -var="azure_openai_endpoint=https://YOUR_RESOURCE.openai.azure.com" \
  -var="azure_openai_deployment=gpt-4o"
```

### 5. Entra ID admin action

An Entra ID admin must add the deploying user as Owner of the app registration:

Portal -> Entra ID -> App registrations -> my-chat-dev -> Owners -> Add owner

Then re-run `terraform apply` to set the redirect URI.

### 6. Update the frontend with your app's IDs

After terraform apply, get the client ID and tenant ID:

```bash
terraform output client_id
terraform output tenant_id
```

Edit `msal-app/frontend/index.html` and replace the placeholder values:

```javascript
const CLIENT_ID = '__CLIENT_ID__';   // ← replace with terraform output client_id
const TENANT_ID = '__TENANT_ID__';   // ← replace with terraform output tenant_id
```

Then rebuild and push the Docker image (step 3) to deploy the updated frontend.

### Group access control (optional)

Works the same as the Easy Auth options. Add `-var="create_access_group=true"` to `terraform apply`. Non-members are blocked at the Microsoft login page (AADSTS50105) — they never reach your app.

---

## Local development

### Easy Auth options (A and B)

Note: Easy Auth only works when deployed to Azure. Locally, the `/.auth/me` endpoint won't exist, so the username won't display. The chat API works normally.

**Container App backend:**

```bash
cd container-app
pip install -r requirements.txt
cp -r ../frontend static
cp ../.env.example .env   # edit with your values

# Load .env and run
export $(cat .env | xargs)
uvicorn server:app --reload
```

Open http://localhost:8000 in your browser.

**Static Web App (SWA CLI):**

```bash
npm install -g @azure/static-web-apps-cli
cd api && npm install && cd ..
swa start frontend --api-location api
```

The SWA CLI emulates the auth endpoints locally, so `/.auth/me` works in dev.

### MSAL option (C)

MSAL works locally — this is one of its advantages over Easy Auth. You need a separate app registration for localhost (since the redirect URI differs), or you can add `http://localhost:8000` as an additional redirect URI to your existing registration.

**Add localhost redirect URI (one-time setup):**

```
Portal: Entra ID -> App registrations -> <your app> -> Authentication
  -> Add a platform -> Single-page application
  -> Redirect URI: http://localhost:8000
  -> Save
```

**Run locally:**

```bash
cd msal-app
pip install -r requirements.txt
cp -r frontend/ static/
cp ../.env.example .env   # edit with your values, plus:
# AZURE_TENANT_ID=your-tenant-id
# AZURE_CLIENT_ID=your-client-id

# Load .env and run
export $(cat .env | xargs)
uvicorn server:app --reload
```

Open http://localhost:8000 in your browser. The full login flow works — you'll be redirected to Microsoft login and back to localhost.

---

## Project structure

```
azure-entra-starter/
├── frontend/                         # Shared chat UI (Alpine.js) — Easy Auth options
│   ├── index.html
│   └── staticwebapp.config.json      # Auth + routing (SWA only)
├── api/                              # Azure Functions backend (SWA option)
│   ├── host.json
│   ├── package.json
│   └── src/functions/
│       ├── chat.js                   # Chat completion endpoint
│       └── getRoles.js               # Group-to-role mapping
├── container-app/                    # FastAPI backend (Container App option)
│   ├── server.py                     # Chat endpoint with streaming
│   ├── requirements.txt
│   └── Dockerfile
├── msal-app/                         # MSAL option — auth in application code
│   ├── frontend/
│   │   └── index.html                # Chat UI with MSAL.js login
│   ├── server.py                     # FastAPI with JWT validation
│   ├── requirements.txt
│   └── Dockerfile
├── .env.example                      # Environment variables template
└── terraform/
    ├── static-web-app/               # Option A: SWA + Easy Auth (self-contained)
    │   ├── main.tf, auth.tf          #   app registration, SWA resource
    │   ├── providers.tf, variables.tf, outputs.tf
    ├── container-app/                # Option B: Container App + Easy Auth (self-contained)
    │   ├── main.tf, auth.tf          #   app registration, Easy Auth config
    │   ├── container.tf              #   ACR, Container App, probes
    │   ├── providers.tf, variables.tf, outputs.tf
    └── msal-app/                     # Option C: Container App + MSAL (self-contained)
        ├── auth.tf                   #   SPA app registration (no Easy Auth)
        ├── main.tf                   #   Key Vault
        ├── container.tf              #   ACR, Container App (no auth proxy)
        ├── groups.tf                 #   access control groups
        ├── providers.tf, variables.tf, outputs.tf
```

## Terraform files — what each one does

Each option has a small set of `.tf` files. Here's what they contain and why:

### Static Web App (`terraform/static-web-app/`)

| File | What it creates | Why |
|------|----------------|-----|
| `auth.tf` | App registration, service principal, client secret, redirect URI | Registers your app with Entra ID so Microsoft login works. The client secret is required by SWA (unlike Container Apps). |
| `main.tf` | Static Web App resource, app settings | The hosting platform itself. App settings inject your OpenAI credentials and the Entra ID client ID/secret. |
| `providers.tf` | Provider versions (azurerm, azuread) | Pins provider versions so builds are reproducible. |
| `variables.tf` | Input variables | Everything configurable: project name, region, OpenAI settings, group ID. |
| `outputs.tf` | URL, deployment token, tenant ID, client ID | Values you need after deploy: the app URL, the SWA CLI deployment token, and the tenant ID to put in `staticwebapp.config.json`. |

### Container App (`terraform/container-app/`)

| File | What it creates | Why |
|------|----------------|-----|
| `auth.tf` | App registration, service principal, redirect URI, Easy Auth config | Registers your app with Entra ID and configures the Easy Auth reverse proxy on the Container App. The auth config uses `azapi` (Azure REST API) since `azurerm` doesn't have a dedicated resource for it. |
| `main.tf` | Key Vault, RBAC role assignments | Stores the OpenAI API key securely. The container reads it via managed identity — no key in code or environment. |
| `container.tf` | Container Registry, Log Analytics, Container App Environment, Container App | The hosting stack: registry for your Docker image, logging, and the container itself with health probes and env vars. |
| `providers.tf` | Provider versions (azurerm, azapi, azuread) | Same as SWA plus `azapi` for Easy Auth. |
| `variables.tf` | Input variables | Project name, region, OpenAI endpoint/deployment, system prompt. |
| `outputs.tf` | URL, registry address, client ID, Key Vault name | Values you need after deploy: the app URL, where to push your Docker image, and the Key Vault name for storing secrets. |

### MSAL App (`terraform/msal-app/`)

| File | What it creates | Why |
|------|----------------|-----|
| `auth.tf` | SPA app registration, service principal, redirect URI | Registers your app with Entra ID as a Single Page Application. Uses PKCE instead of a client secret — the browser handles login directly. No Easy Auth proxy configured. |
| `main.tf` | Key Vault, RBAC role assignments | Same as Container App option — stores the OpenAI API key securely. |
| `container.tf` | Container Registry, Log Analytics, Container App Environment, Container App | Same hosting stack as Container App option, but **without Easy Auth**. The Container App receives all requests directly — your backend validates tokens. Compare with the Easy Auth option to see what's missing (no `azapi_resource` for auth). |
| `groups.tf` | Security group, role assignment, group members | Same group-based access control as the other options. Entra ID blocks non-members at login, before they ever get a token. |
| `providers.tf` | Provider versions (azurerm, azuread) | Simpler than Easy Auth — no `azapi` provider needed since there's no auth proxy to configure. |
| `variables.tf` | Input variables | Same as Container App option. |
| `outputs.tf` | URL, registry address, client ID, **tenant ID**, Key Vault name | Like Container App, plus tenant ID — you need both client ID and tenant ID to configure the MSAL frontend. |

## Customization

| What                | How                                                        |
|---------------------|------------------------------------------------------------|
| System prompt       | `SYSTEM_PROMPT` env var / Terraform variable               |
| Model               | `AZURE_OPENAI_DEPLOYMENT` env var / Terraform variable     |
| Frontend (A/B)      | Edit `frontend/index.html` — no build step                 |
| Frontend (C)        | Edit `msal-app/frontend/index.html` — no build step        |
| Auth (A/B)          | Platform-managed via Easy Auth — no app code changes       |
| Auth (C)            | MSAL.js in frontend + JWT validation in backend            |
| Group restrictions  | `create_access_group = true` in Terraform (all options)    |

## Common questions

**Can I use a custom domain?**
Yes. Both Static Web Apps and Container Apps support custom domains via the Azure portal. Add a CNAME record pointing to your app's default hostname, then configure the custom domain in Azure.

**Can I use a different LLM provider?**
Yes. Edit `container-app/server.py` or `api/src/functions/chat.js` to use any OpenAI-compatible API. The frontend doesn't care what backend you use — it just sends messages to `POST /api/chat`.

**How do I add more API endpoints?**
For Container Apps: add more route handlers in `server.py`. For Static Web Apps: add more function files in `api/src/functions/`. Both are standard FastAPI / Azure Functions patterns.

**What if I need a database?**
Add the resource to the relevant Terraform directory. For Container Apps, grant the managed identity access via RBAC (same pattern as the Key Vault access in `main.tf`). For Static Web Apps, pass the connection string as an app setting.

**How do I update the deployed app?**
Container App: rebuild and push the Docker image, then restart the container app (or it picks up `:latest` on next revision). Static Web App: re-run `swa deploy` with the same deployment token.
