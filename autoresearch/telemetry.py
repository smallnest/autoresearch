from __future__ import annotations

import json
from datetime import datetime
from pathlib import Path


class MetricsRecorder:
    def __init__(self, project_root: Path, enabled: bool = True):
        self.project_root = project_root
        self.enabled = enabled

    @property
    def path(self) -> Path:
        return self.project_root / ".autoresearch" / "metrics.jsonl"

    def record(self, event_type: str, **payload: object) -> None:
        if not self.enabled:
            return
        self.path.parent.mkdir(parents=True, exist_ok=True)
        event = {
            "timestamp": datetime.now().astimezone().isoformat(timespec="seconds"),
            "event": event_type,
            **payload,
        }
        with self.path.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(event, ensure_ascii=False) + "\n")
