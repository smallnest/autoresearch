from __future__ import annotations

import time
from dataclasses import dataclass

from .queue_runner import QueueRunResult, QueueRunner


@dataclass(slots=True)
class DaemonRunResult:
    cycles: int = 0
    processed: int = 0
    succeeded: int = 0
    failed: int = 0


class QueueDaemon:
    def __init__(self, queue_runner: QueueRunner, *, poll_interval: int):
        self.queue_runner = queue_runner
        self.poll_interval = poll_interval

    def run(self, *, batch_size: int, max_cycles: int | None = None) -> DaemonRunResult:
        result = DaemonRunResult()
        while max_cycles is None or result.cycles < max_cycles:
            cycle_result = self.queue_runner.run_batch(batch_size)
            result.cycles += 1
            result.processed += cycle_result.processed
            result.succeeded += cycle_result.succeeded
            result.failed += cycle_result.failed
            if max_cycles is not None and result.cycles >= max_cycles:
                break
            time.sleep(self.poll_interval)
        return result
