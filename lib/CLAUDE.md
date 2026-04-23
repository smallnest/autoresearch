# lib

## 架构约定
- 存放共享的 Shell 脚本和逻辑库。
- `agent_logic.sh`: 包含 Agent 列表解析、审核者轮转等核心共享函数。
- `git_push.sh`: 包含 `git push` 容错与恢复建议逻辑，供 `run.sh` 和测试复用。
- `branch_cleanup.sh`: 包含 PR 合并后的 branch 清理容错逻辑，要求失败只记录告警，不影响后续 comment/close 流程。

## 注意事项
- 脚本应保持 POSIX 兼容性或明确使用 bash。
- 修改共享逻辑时，必须确保不破坏现有 Agent 的调用约定。
- 对 `set -e` 敏感的命令失败路径，优先封装到共享函数中，并在函数内部使用 `cmd || { ... }` 或 `if ! cmd; then ... fi` 保护。
