"""Hub configuration (pydantic-settings). Env prefix: VERITY_."""
from __future__ import annotations

from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="VERITY_", env_file=".env", extra="ignore")

    database_url: str = "postgresql://postgres:postgres@localhost:5432/verity"

    # --- environment & auth (user-authentication.md) ---
    env: str = "local"  # VERITY_ENV: local | prod  (NFR-001a)
    auth_mode: str = "entra"  # entra | mock   (FR-030; mock = local-dev backdoor)
    session_secret: str = ""  # FR-013a: >=256-bit CSPRNG, per-env; checked at startup

    # mock principal (FR-030) — used ONLY when auth_mode=mock && verity_env=local
    mock_tenant_id: str = "00000000-0000-0000-0000-000000000000"
    mock_microsoft_oid: str = "11111111-1111-1111-1111-111111111111"
    mock_display_name: str = "Local Dev"
    mock_email: str | None = "dev@localhost"
    mock_platform_roles: str = "security,viewer"  # comma-separated reference.role codes

    log_level: str = "INFO"

    @property
    def mock_roles(self) -> list[str]:
        return [r.strip() for r in self.mock_platform_roles.split(",") if r.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()


def validate_startup(s: Settings) -> None:
    """Fail-closed startup guardrails (FR-030, NFR-001a). Raises => the service won't serve."""
    if s.auth_mode == "mock" and s.env != "local":
        raise RuntimeError(
            "FATAL: VERITY_AUTH_MODE=mock is only allowed when VERITY_ENV=local (FR-030)."
        )
    if s.env == "prod" and s.auth_mode == "entra" and len(s.session_secret) < 32:
        raise RuntimeError("FATAL: a per-env session_secret (>=256-bit) is required in prod (FR-013a).")
