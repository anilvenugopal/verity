"""Hub configuration (pydantic-settings). Env prefix: VERITY_."""
from __future__ import annotations

from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="VERITY_", env_file=".env", extra="ignore")

    # postgresql://user:pass@host:5432/verity
    database_url: str = "postgresql://postgres:postgres@localhost:5432/verity"
    auth_mode: str = "entra"  # entra | mock (mock = local-dev backdoor, never prod)
    log_level: str = "INFO"


@lru_cache
def get_settings() -> Settings:
    return Settings()
