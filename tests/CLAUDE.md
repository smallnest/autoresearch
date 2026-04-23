# tests

## 架构约定
- 存放项目的测试脚本。
- `test_extract_score.sh`: 测试分数提取逻辑。
- `test_agent_logic.sh`: 测试 Agent 列表解析和轮转逻辑。
- `test_archive.sh`: 测试运行归档机制逻辑。
- `test_context_overflow.sh`: 测试上下文溢出检测与交接逻辑。
- `test_cleanup.sh`: 测试全局 cleanup、trap 幂等和临时文件/子进程回收逻辑。
- `test_branch_cleanup.sh`: 测试 post-merge branch cleanup 的非致命失败日志与继续执行行为。
- `test_git_push.sh`: 测试 git push 失败处理逻辑（set -e 兼容、日志写入、stash 重试）。
- `test_git_error_handling.sh`: 综合测试 Git 操作容错（gh pr merge 失败、branch cleanup 失败、日志记录正确性）。

## 注意事项
- 测试脚本应能独立运行，不依赖外部 API。
- 使用 `assert` 风格的函数进行验证。
- 遵循项目现有的测试模式。
- 对 shell 运行时行为的测试，优先抽取 `run.sh` 中的函数做隔离验证，不直接 `source run.sh`。
- 涉及进程树的测试要允许宿主环境差异；必要时使用 mock 进程树验证递归清理逻辑，而不是依赖平台特定的 `pgrep` 行为。
- 对 Git/CLI 失败路径，优先 mock `git` 子命令并断言日志、返回码和重试次数，避免依赖真实远端或网络环境。
