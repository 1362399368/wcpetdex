"""Configuration shared by local runs, systemd and containers; no cloud SDK."""
from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Mapping


@dataclass(frozen=True)
class Settings:
    host: str
    port: int
    db_path: str
    admin_token: str = field(repr=False)

    @classmethod
    def from_environment(cls, env: Mapping[str, str]):
        token_file = env.get("PETPAIR_ADMIN_TOKEN_FILE", "")
        token = env.get("PETPAIR_ADMIN_TOKEN", "")
        if token_file and token:
            raise ValueError("configure only PETPAIR_ADMIN_TOKEN_FILE or PETPAIR_ADMIN_TOKEN")
        if token_file:
            token = Path(token_file).read_text(encoding="utf-8").strip()
        if len(token) < 32:
            raise ValueError("admin token must contain at least 32 characters")
        try:
            port = int(env.get("PETPAIR_PORT", "8765"))
        except ValueError:
            raise ValueError("PETPAIR_PORT must be a number") from None
        if not 1 <= port <= 65535:
            raise ValueError("PETPAIR_PORT must be between 1 and 65535")
        return cls(
            host=env.get("PETPAIR_HOST", "127.0.0.1"),
            port=port,
            db_path=env.get("PETPAIR_DB", "data/petpair.sqlite3"),
            admin_token=token,
        )
