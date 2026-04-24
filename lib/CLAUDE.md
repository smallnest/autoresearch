# lib

## 架构约定
- 存放共享的 Shell 脚本和逻辑库，由 `run.sh` 在启动时 source。
- 每个库文件专注于一个独立的功能域，通过全局变量和回调函数与 `run.sh` 交互。
- 修改共享逻辑时，必须确保不破坏现有 Agent 的调用约定。
- 对 `set -e` 敏感的命令失败路径，优先封装到共享函数中，并在函数内部使用 `cmd || { ... }` 或 `if ! cmd; then ... fi` 保护。

## 库文件

| 文件 | 职责 | 关键函数 |
|------|------|----------|
| `agent_logic.sh` | Agent 列表解析、审核者轮转 | `parse_agent_list`, `get_review_agent` |
| `git_push.sh` | git push 容错与恢复 | `push_branch_with_recovery` |
| `branch_cleanup.sh` | PR 合并后 branch 清理 | `cleanup_merged_branch` |
| `context.sh` | 上下文溢出检测与压缩 | `detect_context_overflow`, `compress_context`, `handle_context_overflow` |
| `prompt.sh` | Prompt 裁剪与 program.md 读取 | `trim_prompt_smart`, `apply_prompt_trimming`, `get_program_instructions` |
| `subtask.sh` | 子任务 CRUD 与 prompt 注入 | `has_subtasks`, `mark_subtask_passed`, `get_subtask_section` |
| `scoring.sh` | 评分提取与阈值判断 | `extract_score`, `check_score_passed`, `check_sentinel` |
| `progress.sh` | 跨迭代经验日志 | `append_to_progress`, `get_progress_section`, `init_progress` |
| `ui_verify.sh` | UI 验证（截图+LLM） | `run_ui_verification`, `capture_screenshot`, `verify_ui_with_llm` |

## 注意事项
- 脚本应保持 bash 兼容。
- 库文件中的函数依赖 `run.sh` 中的全局变量和回调函数（如 `log`, `log_console`, `error`, `register_temp_file`），这些必须在 source 之前定义。
- 测试文件中如需使用库函数，可以直接 source 对应库文件，或从库文件中提取函数做隔离测试。
