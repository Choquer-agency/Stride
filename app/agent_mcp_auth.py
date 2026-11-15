"""Bearer-token gate for every HTTP request under /mcp."""

import hmac
import os


class AgentTokenMiddleware:
    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http" or not (scope["path"] == "/mcp" or scope["path"].startswith("/mcp/")):
            await self.app(scope, receive, send)
            return

        token = os.environ.get("STRIDE_AGENT_TOKEN", "")
        authorization = next((value.decode("latin-1") for key, value in scope["headers"]
                              if key.lower() == b"authorization"), "")
        prefix = "Bearer "
        supplied = authorization[len(prefix):] if authorization.startswith(prefix) else ""
        if token and supplied and hmac.compare_digest(supplied, token):
            await self.app(scope, receive, send)
            return

        status = 503 if not token else 401
        body = b'{"detail":"Agent MCP is disabled"}' if not token else b'{"detail":"Invalid bearer token"}'
        headers = [(b"content-type", b"application/json"), (b"cache-control", b"no-store")]
        if status == 401:
            headers.append((b"www-authenticate", b"Bearer"))
        await send({"type": "http.response.start", "status": status, "headers": headers})
        await send({"type": "http.response.body", "body": body})
