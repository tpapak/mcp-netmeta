"""
NetMeta Verify MCP HTTP Server

Run the verifier MCP server with Streamable HTTP transport for web deployment.

When deployed behind a reverse proxy at /mcp/netmeta-verify, set
ROOT_PATH=/mcp/netmeta-verify so the server generates correct URLs.

Example nginx config:
    location /mcp/netmeta-verify/ {
        proxy_pass http://localhost:8001/;
    }
"""

import contextlib
import os

from starlette.applications import Starlette
from starlette.middleware.cors import CORSMiddleware

from .server import mcp


@contextlib.asynccontextmanager
async def lifespan(app: Starlette):
    async with mcp.session_manager.run():
        yield


http_app = mcp.streamable_http_app()
app = Starlette(
    routes=http_app.routes,
    lifespan=lifespan,
)

app = CORSMiddleware(
    app,
    allow_origins=["*"],
    allow_methods=["GET", "POST", "DELETE"],
    expose_headers=["Mcp-Session-Id"],
)


def main():
    """Run the HTTP server."""
    import uvicorn

    host = os.environ.get("HOST", "0.0.0.0")
    port = int(os.environ.get("PORT", "8001"))
    root_path = os.environ.get("ROOT_PATH", "")

    uvicorn.run(
        "netmeta_verify.http_server:app",
        host=host,
        port=port,
        root_path=root_path,
        reload=False,
    )


if __name__ == "__main__":
    main()
