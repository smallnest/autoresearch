from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path


@dataclass(slots=True)
class MetricsSummary:
    total_runs: int = 0
    completed_runs: int = 0
    awaiting_approval_runs: int = 0
    failed_runs: int = 0
    auto_merged_runs: int = 0
    avg_iterations: float = 0.0
    avg_score: float = 0.0


def load_metrics(metrics_path: Path) -> list[dict[str, object]]:
    if not metrics_path.exists():
        return []
    events: list[dict[str, object]] = []
    for line in metrics_path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            payload = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(payload, dict):
            events.append(payload)
    return events


def summarize_metrics(events: list[dict[str, object]]) -> MetricsSummary:
    summary = MetricsSummary()
    run_events = [event for event in events if event.get("event") == "run_finished"]
    finalization_events = [event for event in events if event.get("event") == "finalization"]

    summary.total_runs = len(run_events)
    summary.completed_runs = sum(1 for event in run_events if event.get("status") == "completed")
    summary.awaiting_approval_runs = sum(1 for event in run_events if event.get("status") == "awaiting_approval")
    summary.failed_runs = sum(1 for event in run_events if event.get("status") not in {"completed", "awaiting_approval"})
    summary.auto_merged_runs = sum(1 for event in finalization_events if event.get("auto_merged") is True)

    if run_events:
        total_iterations = sum(int(event.get("iterations", 0) or 0) for event in run_events)
        total_score = sum(int(event.get("final_score", 0) or 0) for event in run_events)
        summary.avg_iterations = total_iterations / len(run_events)
        summary.avg_score = total_score / len(run_events)
    return summary


def format_metrics_summary(summary: MetricsSummary) -> str:
    if summary.total_runs == 0:
        return "暂无运行指标。"
    auto_merge_rate = (summary.auto_merged_runs / summary.total_runs) * 100 if summary.total_runs else 0.0
    completion_rate = (summary.completed_runs / summary.total_runs) * 100 if summary.total_runs else 0.0
    return (
        "Autoresearch Metrics\n"
        f"- Total runs: {summary.total_runs}\n"
        f"- Completed: {summary.completed_runs}\n"
        f"- Awaiting approval: {summary.awaiting_approval_runs}\n"
        f"- Failed: {summary.failed_runs}\n"
        f"- Auto merged: {summary.auto_merged_runs} ({auto_merge_rate:.1f}%)\n"
        f"- Completion rate: {completion_rate:.1f}%\n"
        f"- Avg iterations: {summary.avg_iterations:.2f}\n"
        f"- Avg score: {summary.avg_score:.2f}\n"
    )
