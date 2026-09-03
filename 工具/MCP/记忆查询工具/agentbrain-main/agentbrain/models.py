from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path


@dataclass
class Lesson:
    lesson_id: str
    case_id: str
    source_summary: str
    content: str = ""
    tags: list[str] = field(default_factory=list)
    created_at: str = ""
    last_verified_at: str = ""
    valid_until: str = ""
    confidence: float = 0.5
    verified: bool = False
    superseded_by: str = ""
    use_count: int = 0
    failure_count: int = 0
    retrieval_count: int = 0
    revision: int = 1
    path: Path | None = None
