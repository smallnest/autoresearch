from __future__ import annotations

import json
from pathlib import Path

from .models import TaskItem


class TaskPayloadError(RuntimeError):
    pass


class TaskManager:
    def __init__(self, work_dir: Path):
        self.work_dir = work_dir

    @property
    def path(self) -> Path:
        return self.work_dir / "tasks.json"

    def exists(self) -> bool:
        return self.path.exists()

    def load(self) -> dict[str, object] | None:
        if not self.path.exists():
            return None
        try:
            payload = json.loads(self.path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            return None
        if not isinstance(payload, dict):
            return None
        return payload

    def has_subtasks(self) -> bool:
        payload = self.load()
        if not payload:
            return False
        subtasks = payload.get("subtasks")
        return isinstance(subtasks, list) and len(subtasks) > 0

    def save_payload(self, payload: dict[str, object]) -> int:
        raw_subtasks = payload.get("subtasks")
        if not isinstance(raw_subtasks, list):
            raise TaskPayloadError("规划输出缺少 subtasks 列表")
        subtasks = [TaskItem.from_payload(item) for item in raw_subtasks if isinstance(item, dict)]
        subtasks.sort(key=lambda item: (item.priority, item.id))
        normalized = {
            "issueNumber": int(payload.get("issueNumber", 0) or 0),
            "subtasks": [item.to_payload() for item in subtasks],
        }
        self.path.write_text(json.dumps(normalized, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        return len(subtasks)

    def items(self) -> list[TaskItem]:
        payload = self.load() or {}
        raw_subtasks = payload.get("subtasks") or []
        if not isinstance(raw_subtasks, list):
            return []
        return [TaskItem.from_payload(item) for item in raw_subtasks if isinstance(item, dict)]

    def _write_items(self, items: list[TaskItem]) -> None:
        payload = self.load() or {}
        issue_number = int(payload.get("issueNumber", 0) or 0)
        normalized = {
            "issueNumber": issue_number,
            "subtasks": [item.to_payload() for item in items],
        }
        self.path.write_text(json.dumps(normalized, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    def current(self) -> TaskItem | None:
        for item in self.items():
            if not item.passes:
                return item
        return None

    def current_id(self) -> str:
        task = self.current()
        return task.id if task else ""

    def current_title(self) -> str:
        task = self.current()
        return task.title if task else ""

    def mark_passed(self, task_id: str) -> None:
        items = self.items()
        changed = False
        for item in items:
            if item.id == task_id:
                item.passes = True
                changed = True
                break
        if changed:
            self._write_items(items)

    def all_passed(self) -> bool:
        if not self.path.exists():
            return True
        return all(item.passes for item in self.items())

    def is_ui_current(self) -> bool:
        task = self.current()
        return bool(task and task.task_type == "ui")

    def progress_summary(self) -> str:
        items = self.items()
        if not items:
            return ""
        passed = sum(1 for item in items if item.passes)
        task = self.current()
        current_id = task.id if task else ""
        current_title = task.title if task else ""
        return f"子任务进度: {passed}/{len(items)} 已完成 | 当前子任务: {current_id} - {current_title}"

    def subtask_section(self) -> str:
        task = self.current()
        if not task:
            return ""
        criteria = "\n".join(f"  - {line}" for line in task.acceptance_criteria)
        ui_hint = ""
        if task.task_type == "ui":
            ui_hint = (
                "\n\n⚠️ **UI 类型任务**: 此子任务涉及 UI 变更，实现时请注意：\n"
                "- 确保页面布局、样式正确渲染\n"
                "- 确保交互元素（按钮、表单、链接等）功能正常\n"
                "- 确保无 console 错误或页面崩溃\n"
                "- 实现完成后将进行浏览器截图验证"
            )
        return (
            "\n## 当前子任务\n\n"
            f"{self.progress_summary()}\n\n"
            "### 子任务详情\n\n"
            f"- **ID**: {task.id}\n"
            f"- **标题**: {task.title}\n"
            f"- **类型**: {task.task_type}\n"
            f"- **描述**: {task.description}\n"
            "- **验收条件**:\n"
            f"{criteria}\n"
            f"{ui_hint}\n"
            "请专注于实现此子任务，不要处理其他子任务。完成此子任务后等待审核。"
        )

    def review_section(self) -> str:
        if not self.path.exists():
            return ""
        task = self.current()
        if not task:
            return f"\n## 子任务审核\n\n{self.progress_summary()}\n\n所有子任务已完成审核。"
        criteria = "\n".join(f"  - {line}" for line in task.acceptance_criteria)
        ui_section = ""
        if task.task_type == "ui":
            ui_section = (
                "\n\n### UI 验证标准（此子任务为 UI 类型）\n\n"
                "审核时请额外关注以下 UI 验证标准：\n"
                "- 页面无空白或崩溃：页面能正常加载，无白屏或错误页面\n"
                "- 关键元素可见：页面标题、内容、导航等关键元素正确渲染\n"
                "- 交互元素可点击：按钮、链接、表单等可正常交互\n"
                "- 无 console 错误：浏览器控制台无 JavaScript 错误\n"
                "- 样式一致性：CSS 样式与设计稿或现有风格一致\n"
                "- 响应式布局：在不同屏幕尺寸下布局合理（如适用）\n\n"
                "此子任务通过代码审核后，将进行浏览器截图验证以确认 UI 渲染正确。"
            )
        return (
            "\n## 子任务审核\n\n"
            f"{self.progress_summary()}\n\n"
            "请审核当前子任务的实现：\n\n"
            f"- **ID**: {task.id}\n"
            f"- **标题**: {task.title}\n"
            f"- **类型**: {task.task_type}\n"
            f"- **描述**: {task.description}\n"
            "- **验收条件**:\n"
            f"{criteria}\n"
            f"{ui_section}\n\n"
            "请针对此子任务的验收条件进行审核。"
        )
