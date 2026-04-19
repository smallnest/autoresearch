# tests

## 架构约定
- 存放项目的测试脚本。
- `test_extract_score.sh`: 测试分数提取逻辑。
- `test_agent_logic.sh`: 测试 Agent 列表解析和轮转逻辑。
- `test_archive.sh`: 测试运行归档机制逻辑。

## 注意事项
- 测试脚本应能独立运行，不依赖外部 API。
- 使用 `assert` 风格的函数进行验证。
- 遵循项目现有的测试模式。
