"""Local stdio entry point for the same coaching tools served at /mcp/."""

import sys
from pathlib import Path

from dotenv import load_dotenv

load_dotenv("/Users/brycechoquer/Desktop/Stride v.2/.env")
load_dotenv()
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.agent_mcp import server  # noqa: E402


if __name__ == "__main__":
    server.run(transport="stdio")
