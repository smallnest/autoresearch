# tests

## 架构约定
- 存放项目的测试脚本。
- `test_extract_score.sh`: 测试分数提取逻辑。
- `test_agent_logic.sh`: 测试 Agent 列表解析和轮转逻辑。
- `test_archive.sh`: 测试运行归档机制逻辑。
- `test_context_overflow.sh`: 测试上下文溢出检测与交接逻辑。
- `test_cleanup.sh`: 测试全局 cleanup、trap 幂等和临时文件/子进程回收逻辑。

## 注意事项
- 测试脚本应能独立运行，不依赖外部 API。
- 使用 `assert` 风格的函数进行验证。
- 遵循项目现有的测试模式。
- 对 shell 运行时行为的测试，优先抽取 `run.sh` 中的函数做隔离验证，不直接 `source run.sh`。
- 涉及进程树的测试要允许宿主环境差异；必要时使用 mock 进程树验证递归清理逻辑，而不是依赖平台特定的 `pgrep` 行为。
