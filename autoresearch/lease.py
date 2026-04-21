from __future__ import annotations

import json
import os
import socket
import threading
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path


def default_worker_id() -> str:
    return f"{socket.gethostname()}-{os.getpid()}"


@dataclass(slots=True)
class LeaseRecord:
    resource_id: str
    owner: str
    pid: int
    hostname: str
    acquired_at: str
    heartbeat_at: str
    expires_at: str

    def to_payload(self) -> dict[str, object]:
        return {
            "resource_id": self.resource_id,
            "owner": self.owner,
            "pid": self.pid,
            "hostname": self.hostname,
            "acquired_at": self.acquired_at,
            "heartbeat_at": self.heartbeat_at,
            "expires_at": self.expires_at,
        }

    @classmethod
    def from_payload(cls, payload: dict[str, object]) -> "LeaseRecord":
        return cls(
            resource_id=str(payload.get("resource_id", "")),
            owner=str(payload.get("owner", "")),
            pid=int(payload.get("pid", 0) or 0),
            hostname=str(payload.get("hostname", "")),
            acquired_at=str(payload.get("acquired_at", "")),
            heartbeat_at=str(payload.get("heartbeat_at", "")),
            expires_at=str(payload.get("expires_at", "")),
        )

    def is_expired(self, now_ts: float | None = None) -> bool:
        now = datetime.fromtimestamp(now_ts or time.time(), tz=timezone.utc)
        try:
            expiry = datetime.fromisoformat(self.expires_at.replace("Z", "+00:00"))
        except ValueError:
            return True
        return now >= expiry


class LeaseHandle:
    def __init__(self, manager: "LeaseManager", resource_id: str, owner: str, ttl_seconds: int):
        self.manager = manager
        self.resource_id = resource_id
        self.owner = owner
        self.ttl_seconds = ttl_seconds
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None

    def __enter__(self) -> "LeaseHandle":
        self.start_heartbeat()
        return self

    def __exit__(self, exc_type, exc, tb) -> None:
        self.release()

    def start_heartbeat(self) -> None:
        interval = max(1, self.ttl_seconds // 3)
        self._thread = threading.Thread(target=self._heartbeat_loop, args=(interval,), daemon=True)
        self._thread.start()

    def _heartbeat_loop(self, interval: int) -> None:
        while not self._stop.wait(interval):
            self.manager.renew(self.resource_id, self.owner, self.ttl_seconds)

    def release(self) -> None:
        self._stop.set()
        if self._thread and self._thread.is_alive():
            self._thread.join(timeout=1)
        self.manager.release(self.resource_id, self.owner)


class LeaseManager:
    def __init__(self, root: Path):
        self.root = root
        self.root.mkdir(parents=True, exist_ok=True)

    def acquire(self, resource_id: str, owner: str, ttl_seconds: int) -> LeaseHandle | None:
        with self._guard(resource_id):
            record = self._read(resource_id)
            if record and not record.is_expired() and record.owner != owner:
                return None
            self._write(resource_id, self._new_record(resource_id, owner, ttl_seconds))
        return LeaseHandle(self, resource_id, owner, ttl_seconds)

    def renew(self, resource_id: str, owner: str, ttl_seconds: int) -> bool:
        with self._guard(resource_id):
            record = self._read(resource_id)
            if not record or record.owner != owner:
                return False
            self._write(resource_id, self._new_record(resource_id, owner, ttl_seconds, acquired_at=record.acquired_at))
            return True

    def release(self, resource_id: str, owner: str) -> None:
        with self._guard(resource_id):
            record = self._read(resource_id)
            if record and record.owner == owner:
                lease_path = self._lease_path(resource_id)
                if lease_path.exists():
                    lease_path.unlink()

    def get(self, resource_id: str) -> LeaseRecord | None:
        return self._read(resource_id)

    def _new_record(self, resource_id: str, owner: str, ttl_seconds: int, acquired_at: str | None = None) -> LeaseRecord:
        now = datetime.now(timezone.utc)
        expiry = now.timestamp() + ttl_seconds
        return LeaseRecord(
            resource_id=resource_id,
            owner=owner,
            pid=os.getpid(),
            hostname=socket.gethostname(),
            acquired_at=acquired_at or now.isoformat(),
            heartbeat_at=now.isoformat(),
            expires_at=datetime.fromtimestamp(expiry, tz=timezone.utc).isoformat(),
        )

    def _lease_path(self, resource_id: str) -> Path:
        safe_name = resource_id.replace("/", "_")
        return self.root / f"{safe_name}.json"

    def _lock_path(self, resource_id: str) -> Path:
        safe_name = resource_id.replace("/", "_")
        return self.root / f"{safe_name}.lock"

    def _read(self, resource_id: str) -> LeaseRecord | None:
        path = self._lease_path(resource_id)
        if not path.exists():
            return None
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            return None
        if not isinstance(payload, dict):
            return None
        return LeaseRecord.from_payload(payload)

    def _write(self, resource_id: str, record: LeaseRecord) -> None:
        path = self._lease_path(resource_id)
        path.write_text(json.dumps(record.to_payload(), ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    def _guard(self, resource_id: str):
        return _LeaseGuard(self._lock_path(resource_id))


class _LeaseGuard:
    def __init__(self, lock_path: Path):
        self.lock_path = lock_path
        self.fd: int | None = None

    def __enter__(self) -> "_LeaseGuard":
        self.lock_path.parent.mkdir(parents=True, exist_ok=True)
        deadline = time.time() + 5
        while True:
            try:
                self.fd = os.open(self.lock_path, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
                break
            except FileExistsError:
                if time.time() >= deadline:
                    raise TimeoutError(f"lease lock timeout: {self.lock_path}")
                time.sleep(0.05)
        return self

    def __exit__(self, exc_type, exc, tb) -> None:
        if self.fd is not None:
            os.close(self.fd)
        if self.lock_path.exists():
            self.lock_path.unlink()
