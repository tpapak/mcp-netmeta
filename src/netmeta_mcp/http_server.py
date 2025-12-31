"""
NetMeta MCP HTTP Server

Run the MCP server with Streamable HTTP transport for web deployment.
"""

import contextlib

from starlette.applications import Starlette
from starlette.middleware.cors import CORSMiddleware
from starlette.routing import Mount

from .server import mcp


@contextlib.asynccontextmanager
async def lifespan(app: Starlette):
    """Manage server lifecycle."""
    async with mcp.session_manager.run():
        yield


# Create Starlette app with MCP mounted
app = Starlette(
    routes=[
        Mount("/mcp", app=mcp.streamable_http_app()),
    ],
    lifespan=lifespan,
)

# Add CORS middleware for browser clients
app = CORSMiddleware(
    app,
    allow_origins=["*"],
    allow_methods=["GET", "POST", "DELETE"],
    expose_headers=["Mcp-Session-Id"],
)


def main():
    """Run the HTTP server."""
    import uvicorn

    uvicorn.run(
        "netmeta_mcp.http_server:app",
        host="0.0.0.0",
        port=8000,
        reload=False,
    )


if __name__ == "__main__":
    main()
