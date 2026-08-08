from __future__ import annotations

from dataclasses import dataclass


class ManifestError(ValueError):
    """Raised when native objective data cannot be represented safely."""


@dataclass(frozen=True, slots=True)
class NativeObjective:
    kind: str
    context: str
    native_id: int
    title: str
    source_dat: str
    record_offset: int
    progress_id: int | None = None
    details: tuple[str, ...] = ()

    @property
    def key(self) -> str:
        return f"{self.kind}:{self.context}:{self.native_id}"
