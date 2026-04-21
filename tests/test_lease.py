from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from datetime import datetime, timedelta, timezone

from autoresearch.lease import LeaseManager, LeaseRecord


class LeaseManagerTests(unittest.TestCase):
    def test_acquire_and_release_lease(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            manager = LeaseManager(Path(tmpdir))
            lease = manager.acquire("issue-1", "worker-a", ttl_seconds=60)
            self.assertIsNotNone(lease)
            self.assertIsNotNone(manager.get("issue-1"))
            competing = manager.acquire("issue-1", "worker-b", ttl_seconds=60)
            self.assertIsNone(competing)
            assert lease is not None
            lease.release()
            self.assertIsNone(manager.get("issue-1"))

    def test_expired_lease_can_be_reacquired(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            manager = LeaseManager(Path(tmpdir))
            expired_at = datetime.now(timezone.utc) - timedelta(seconds=10)
            manager._write(
                "issue-2",
                LeaseRecord(
                    resource_id="issue-2",
                    owner="worker-a",
                    pid=123,
                    hostname="host",
                    acquired_at=expired_at.isoformat(),
                    heartbeat_at=expired_at.isoformat(),
                    expires_at=expired_at.isoformat(),
                ),
            )
            reacquired = manager.acquire("issue-2", "worker-b", ttl_seconds=60)
            self.assertIsNotNone(reacquired)


if __name__ == "__main__":
    unittest.main()
