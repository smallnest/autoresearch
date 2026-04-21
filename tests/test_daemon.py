from __future__ import annotations

import unittest

from autoresearch.daemon import QueueDaemon
from autoresearch.queue_runner import QueueRunResult


class FakeQueueRunner:
    def __init__(self):
        self.calls = 0

    def run_batch(self, batch_size: int) -> QueueRunResult:
        self.calls += 1
        return QueueRunResult(processed=batch_size, succeeded=batch_size, failed=0)


class QueueDaemonTests(unittest.TestCase):
    def test_run_fixed_number_of_cycles(self) -> None:
        queue_runner = FakeQueueRunner()
        daemon = QueueDaemon(queue_runner, poll_interval=0)
        result = daemon.run(batch_size=2, max_cycles=3)
        self.assertEqual(queue_runner.calls, 3)
        self.assertEqual(result.cycles, 3)
        self.assertEqual(result.processed, 6)
        self.assertEqual(result.succeeded, 6)


if __name__ == "__main__":
    unittest.main()
