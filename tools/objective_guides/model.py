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


@dataclass(frozen=True, slots=True)
class SourceStep:
    order: int
    marker: str
    depth: int
    source_text: str
    spoken_text: str
    action: str
    linked_entities: tuple[str, ...] = ()
    zone_candidates: tuple[str, ...] = ()
    map_numbers: tuple[str, ...] = ()
    grid_coordinates: tuple[str, ...] = ()
    items: tuple[str, ...] = ()
    key_items: tuple[str, ...] = ()
    warnings: tuple[str, ...] = ()


@dataclass(frozen=True, slots=True)
class ParsedObjective:
    site: str
    page_id: int
    revision_id: int
    canonical_title: str
    kind: str
    objective_name: str
    mission_number: str = ""
    context_hint: str = ""
    aliases: tuple[str, ...] = ()
    categories: tuple[str, ...] = ()
    start_entities: tuple[str, ...] = ()
    steps: tuple[SourceStep, ...] = ()
    warnings: tuple[str, ...] = ()
