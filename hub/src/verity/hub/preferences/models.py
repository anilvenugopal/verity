from __future__ import annotations

from typing import Literal

from pydantic import BaseModel

ThemeMode = Literal["light", "dark", "system"]
ThemePalette = Literal["gray", "slate", "warm"]


class UserPreferences(BaseModel):
    """Resolved preferences — API layer supplies defaults for any key not yet stored."""
    theme_mode: ThemeMode = "system"
    theme_palette: ThemePalette = "gray"


class PreferencesPatch(BaseModel):
    """Partial update — only supplied fields are merged into the stored blob."""
    theme_mode: ThemeMode | None = None
    theme_palette: ThemePalette | None = None
