from __future__ import annotations

import json
from dataclasses import asdict, dataclass, field

from .logic import check_score_passed, check_sentinel, extract_score, load_json_snippet


@dataclass(slots=True)
class ReviewFinding:
    severity: str
    summary: str
    path: str = ""


@dataclass(slots=True)
class ReviewReport:
    passed: bool
    score: int
    risk_level: str = "unknown"
    findings: list[ReviewFinding] = field(default_factory=list)
    required_fixes: list[str] = field(default_factory=list)
    source: str = "heuristic"
    raw_text: str = ""

    def to_payload(self) -> dict[str, object]:
        payload = asdict(self)
        payload["findings"] = [asdict(item) for item in self.findings]
        return payload


def parse_review_report(review_result: str, passing_score: int) -> ReviewReport:
    sentinel = check_sentinel(review_result)
    if sentinel == "pass":
        return ReviewReport(
            passed=True,
            score=100,
            risk_level="low",
            source="sentinel",
            raw_text=review_result,
        )
    if sentinel == "fail":
        return ReviewReport(
            passed=False,
            score=0,
            risk_level="high",
            source="sentinel",
            raw_text=review_result,
        )

    payload = load_json_snippet(review_result)
    if payload:
        report = _report_from_payload(payload, review_result, passing_score)
        if report is not None:
            return report

    score = extract_score(review_result)
    if score == 0:
        score = 50
    return ReviewReport(
        passed=check_score_passed(score, passing_score),
        score=score,
        risk_level="unknown",
        source="heuristic",
        raw_text=review_result,
    )


def format_review_feedback(report: ReviewReport) -> str:
    sections = [
        "请根据以下审核结论修复实现。",
        f"- 评分: {report.score}/100",
        f"- 风险级别: {report.risk_level}",
    ]
    if report.required_fixes:
        sections.append("- 必修复项:")
        sections.extend(f"  - {item}" for item in report.required_fixes)
    if report.findings:
        sections.append("- 主要发现:")
        for item in report.findings:
            location = f" ({item.path})" if item.path else ""
            sections.append(f"  - [{item.severity}] {item.summary}{location}")
    sections.extend(["", "原始审核报告：", report.raw_text])
    return "\n".join(sections)


def write_review_report(report: ReviewReport, path) -> None:
    path.write_text(json.dumps(report.to_payload(), ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def _report_from_payload(payload: dict[str, object], review_result: str, passing_score: int) -> ReviewReport | None:
    has_pass = "pass" in payload
    has_score = "score" in payload
    if not has_pass and not has_score:
        return None

    score_value = payload.get("score", 0)
    try:
        score = int(float(score_value))
    except (TypeError, ValueError):
        score = extract_score(review_result)
    if score == 0 and has_pass and payload.get("pass") is True:
        score = passing_score
    if score == 0 and not has_pass:
        score = 50

    pass_value = payload.get("pass")
    if isinstance(pass_value, bool):
        passed = pass_value
    else:
        passed = check_score_passed(score, passing_score)

    findings_payload = payload.get("findings")
    findings: list[ReviewFinding] = []
    if isinstance(findings_payload, list):
        for item in findings_payload:
            if not isinstance(item, dict):
                continue
            findings.append(
                ReviewFinding(
                    severity=str(item.get("severity", "unknown")),
                    summary=str(item.get("summary", "")),
                    path=str(item.get("path", "")),
                )
            )

    required_fixes_payload = payload.get("requiredFixes", payload.get("required_fixes"))
    required_fixes: list[str] = []
    if isinstance(required_fixes_payload, list):
        required_fixes = [str(item) for item in required_fixes_payload]

    risk_level = str(payload.get("riskLevel", payload.get("risk_level", "unknown")))
    return ReviewReport(
        passed=passed,
        score=score,
        risk_level=risk_level,
        findings=findings,
        required_fixes=required_fixes,
        source="json",
        raw_text=review_result,
    )
