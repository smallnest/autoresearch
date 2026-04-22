# Program - 实现规则与约束

本文档定义 Agent 在实现 Issues 时必须遵循的规则和约束。人类通过修改本文档来控制 Agent 的行为。

> **提示**: 将此文件复制到项目目录 `.autoresearch/program.md` 中进行项目级别的自定义。

---

## 核心目标

实现 GitHub Issues 中的功能需求或 Bug 修复，确保代码质量和测试覆盖。

---

## 权限边界

### Agent 可以做的事情

```
✓ 修改源代码目录下的文件
✓ 创建新的测试文件
✓ 修改现有测试文件
✓ 在 .autoresearch/workflows/ 目录下记录工作日志
✓ 运行测试命令
✓ 运行 lint 命令
✓ 创建本地 git 分支
✓ 提交本地 git commit
```

### Agent 不可以做的事情

```
✗ 修改依赖管理文件（如 go.mod/go.sum, package.json, requirements.txt，除非 Issue 明确要求）
✗ 修改 .github/ 目录下的任何文件
✗ 修改 Makefile / CMakeLists.txt / build.gradle
✗ 修改 Dockerfile 或 docker-compose.yml
✗ 修改 CI/CD 配置文件
✗ 删除任何现有文件
✗ 推送到远程仓库
✗ 关闭 GitHub Issue
✗ 创建 GitHub PR
✗ 修改 .autoresearch/ 目录下的规则文件
✗ 执行任何需要 --force 的 git 命令
```

---

## 代码规范

### 通用规范

```
1. 遵循项目现有代码风格
2. 保持函数简短，单一职责
3. 有意义的命名，避免缩写
4. 适当的错误处理和日志记录
5. 避免硬编码的配置值
```

### Go 代码规范

```
1. 遵循 Effective Go (https://golang.org/doc/effective_go)
2. 遵循 Go Code Review Comments
3. 使用 gofmt 格式化代码
4. 使用 goimports 管理导入
```

### Python 代码规范

```
1. 遵循 PEP 8
2. 使用 type hints
3. 使用 pytest 编写测试
```

### TypeScript/JavaScript 代码规范

```
1. 使用 ESLint + Prettier
2. 严格模式
3. 使用 TypeScript 优先
```

### Rust 代码规范

```
1. 遵循 Rust API Guidelines (https://rust-lang.github.io/api-guidelines/)
2. 使用 rustfmt 格式化代码 (cargo fmt)
3. 使用 clippy 检查代码质量 (cargo clippy)
4. 优先使用 Result<T, E> 处理错误，避免 panic
5. 合理使用 Option<T>，避免不必要的 unwrap()
6. 优先使用借用(&)而非所有权转移，避免不必要的 clone()
7. 使用 Cargo 管理依赖，避免直接修改 Cargo.lock
8. 公共 API 必须编写文档注释 (/// 和 //!)
9. 使用 cargo test 编写单元测试和集成测试
```

### 前端代码规范 (React/Vue/Svelte)

```
1. 组件单一职责，一个文件一个组件
2. Props 使用 TypeScript interface 定义，避免 any
3. 使用函数式组件和 Hooks (React) / Composition API (Vue)
4. 状态管理优先使用框架内置方案，避免过早引入全局状态库
5. CSS 优先使用 CSS Modules / Scoped CSS / Tailwind，避免全局样式污染
6. 事件处理函数命名: handle + 动作 (handleSubmit, handleClick)
7. 列表渲染使用稳定的 key，禁止使用数组 index 作为 key
8. 图片等静态资源使用懒加载
9. 使用 Vitest/Jest 编写组件测试，Testing Library 进行 DOM 测试
10. 遵循项目现有的目录结构约定 (pages/components/hooks/utils 等)
```

---

## 测试规范

### 测试要求

```
- 所有新增功能必须有测试
- 测试覆盖率目标: ≥ 70%
- 使用项目对应的测试框架
- 测试函数命名清晰，体现测试场景
```

> **测试豁免**：如果项目类型或实现内容不适用单元测试（如 Shell 脚本、配置文件、Dockerfile、CI/CD pipeline、文档等），可以不写单元测试，在实现报告中注明"单元测试不适用"及原因。

### 测试禁止事项

```
✗ 不要在测试中使用固定 sleep（使用异步等待/channel 同步）
✗ 不要依赖外部服务（使用 mock）
✗ 不要修改全局状态
✗ 不要跳过失败的测试
```

---

## 迭代控制

### 迭代限制

```
最大迭代次数: 默认 42 次（可通过参数指定）

每次迭代时间预算:
- 简单 Issue: 10 分钟
- 中等 Issue: 30 分钟
- 复杂 Issue: 60 分钟
```

### 终止条件

```
停止迭代的条件:
1. 审核者评分 ≥ 达标线（默认 85 分），且无严重问题
2. 达到最大迭代次数
3. 测试连续失败 3 次
4. Agent 报告无法实现
5. 发现需要人工决策的设计问题
```

---

## 质量检查点

> **借鉴 [ralph](https://github.com/snarktank/ralph) 的质量自检设计：ALL commits must pass quality checks. Do NOT commit broken code.**

### 硬性规则

```
⚠️ MUST: Agent 在认为实现完成之前，MUST 运行项目的 typecheck/lint/test，全部通过后才能提交审核。
⚠️ MUST: 如果检查不通过，MUST 先修复再提交。不得带着已知错误提交审核。
⚠️ MUST: 每次提交前必须逐项确认自检 checklist。
```

### 提交前自检 Checklist

在标记实现完成或提交审核之前，Agent MUST 逐项确认以下清单：

```
MUST 级别（全部通过才能提交）:
- [ ] ✅ 代码可以编译/类型检查通过
- [ ] ✅ Lint 无新增错误
- [ ] ✅ 相关测试通过

SHOULD 级别（尽力满足，未满足时在报告中说明原因）:
- [ ] 新代码有对应的测试覆盖
- [ ] 测试覆盖率 ≥ 80%
- [ ] 所有公共 API 有文档注释
```

### 自检失败处理流程

```
自检失败时 MUST 遵循以下流程：

1. 运行检查 → 发现失败
2. 分析失败原因
3. 修复问题
4. 重新运行检查（回到步骤 1）
5. 全部通过 → 提交审核

禁止行为:
✗ 跳过自检直接提交
✗ 带着已知编译错误提交
✗ 带着已知测试失败提交
✗ 注释掉失败的测试来"通过"自检
✗ 标记 TODO/FIXME 推迟已知问题而不在报告中说明
```

### 各语言自检命令参考

Agent 应根据项目语言运行对应的检查命令。如果项目已有 Makefile 或 scripts 中的检查命令，优先使用项目自带的。

#### Go

```bash
# 编译检查
go build ./...

# 类型检查（比 go build 更严格）
go vet ./...

# Lint
golangci-lint run ./...   # 推荐工具
# 或
go vet ./...

# 测试
go test ./...

# 测试覆盖率
go test -cover ./...
```

#### Python

```bash
# 类型检查
mypy .                    # 或 mypy src/
pyright .                 # 替代方案

# Lint
ruff check .              # 推荐
# 或
flake8 .
pylint src/

# 测试
pytest
pytest --cov              # 带覆盖率

# 格式检查
black --check .
```

#### TypeScript/JavaScript

```bash
# 类型检查
npx tsc --noEmit          # TypeScript 项目
# 或查看 package.json 中的 typecheck script

# Lint
npx eslint .
npx prettier --check .

# 测试
npm test                  # 或 pnpm test / yarn test
npx vitest run            # 或 npx jest

# 构建（验证编译）
npm run build             # 验证产物能正确生成
```

#### Rust

```bash
# 编译检查
cargo build
cargo check               # 更快的编译检查

# Lint
cargo clippy              # MUST 通过 clippy 检查
cargo fmt --check         # 格式检查

# 测试
cargo test

# 完整检查（CI 级别）
cargo clippy -- -D warnings && cargo test
```

#### Shell 脚本

```bash
# 语法检查
bash -n script.sh         # 语法检查
shellcheck script.sh       # Lint

# 无标准测试框架，确认脚本可执行且 exit code 为 0
```

#### 项目自带命令优先

```bash
# 检查项目是否有标准化的检查命令
cat Makefile              # make lint, make test, make check
cat package.json          # npm scripts
cat Cargo.toml            # cargo commands
cat tox.ini / pyproject.toml  # Python 项目配置

# 如果项目有 CI 配置，参考 CI 中运行的检查命令
cat .github/workflows/*.yml
```

---

## 行为准则

> 基于 [forrestchang/andrej-karpathy-skills](https://github.com/forrestchang/andrej-karpathy-skills) 的行为指南，偏向谨慎而非速度。

### 动手前先思考

**不要假设。不要掩盖困惑。揭示权衡。**

实现前：
- 明确陈述你的假设。如果不确定，就问。
- 如果存在多种理解，把它们都列出来，不要沉默地选择一个。
- 如果存在更简单的方案，说出来。必要时提出反对。
- 如果有不明确的地方，停下来，指出困惑之处，然后提问。

### 简洁优先

**用最少的代码解决问题。不做任何推测性设计。**

- 不要实现超出需求的功能。
- 不要为单次使用的代码创建抽象。
- 不要添加未经请求的"灵活性"或"可配置性"。
- 不要为不可能发生的场景添加错误处理。
- 如果你写了 200 行而其实 50 行就够了，重写它。

自问："一个资深工程师会说这太复杂了吗？" 如果是，简化。

### 精准改动

**只改你必须改的。只清理你自己造成的混乱。**

编辑现有代码时：
- 不要"改进"相邻的代码、注释或格式。
- 不要重构没有坏的东西。
- 匹配现有风格，即使你会用不同的方式。
- 如果注意到无关的废弃代码，提一下就好，不要删除。

当你自己的改动产生了孤儿代码时：
- 移除因你的改动而变得未使用的 import/变量/函数。
- 不要移除之前就存在的废弃代码，除非被要求。

检验标准：每一行改动都应该能追溯到 Issue 的需求。

### 目标驱动执行

**定义成功标准。循环直到验证通过。**

将任务转化为可验证的目标：
- "添加验证" → "为无效输入写测试，然后让测试通过"
- "修复 bug" → "写一个能重现它的测试，然后让测试通过"
- "重构 X" → "确保重构前后测试都通过"

多步骤任务应陈述简短计划：
```
1. [步骤] → 验证: [检查方式]
2. [步骤] → 验证: [检查方式]
3. [步骤] → 验证: [检查方式]
4. 最终验证: 运行完整自检 checklist（编译/lint/测试全部通过）
```

**关键要求**：最后一步 MUST 是运行完整的自检 checklist。只有自检全部通过，才算实现完成。

强的成功标准让你能独立循环。弱的标准（"让它能跑"）需要不断澄清。

---

**准则生效的标志：** diff 中更少的不必要改动，更少的过度复杂导致的重写，澄清问题出现在实现之前而非犯错之后。

---

## 安全约束

### 安全检查

```
Agent 必须确保:
✓ 无 SQL 注入风险
✓ 无命令注入风险
✓ 无路径遍历风险
✓ 无敏感信息硬编码
✓ 无不安全的数据反序列化
✓ 输入验证完整
✓ 错误信息不泄露敏感数据
```

---

## 目录级知识积累 (CLAUDE.md)

借鉴 [ralph](https://github.com/snarktank/ralph) 的 `AGENTS.md` 机制。Claude Code / Amp 等工具会自动读取工作目录下的 `CLAUDE.md`，Agent 写入可复用知识后，后续迭代自动生效，实现项目自进化。

### 规则

```
1. 实现完成后，如果在某目录发现了可复用模式，更新该目录的 CLAUDE.md
2. 如果目录下已有 CLAUDE.md，追加新知识（不覆盖已有内容）
3. 如果目录下没有 CLAUDE.md，创建新文件
4. 只写可复用知识，不写临时调试信息和 story 特定内容
```

### 应写入的内容

```
✓ 模块级 API 约定（如 "本模块的 Handler 必须实现 io.Closer 接口"）
✓ 跨文件依赖关系（如 "修改 X 时必须同步更新 Y"）
✓ 项目特有的模式（如 "本模块使用 Z 模式处理 API 调用"）
✓ 重要的架构决策（如 "本包禁止直接访问数据库，必须通过 Repository 接口"）
✓ 常见陷阱（如 "此函数的 ctx 参数不能为 nil，否则会 panic"）
```

### 禁止写入的内容

```
✗ 临时调试信息
✗ 特定 Issue / Story 的上下文
✗ 一次性的 workaround
✗ 敏感信息（密钥、密码、token）
✗ 与代码无直接关系的注释
```

### CLAUDE.md 文件格式

```markdown
# [目录名]

## 架构约定
- [约定1]
- [约定2]

## 依赖关系
- [依赖说明]

## 注意事项
- [常见陷阱或特殊处理]
```

---

## 异常处理

当 Agent 遇到阻塞时，应输出结构化的阻塞报告，说明原因、已尝试的方案和建议操作。

### Tool Call 格式要求

```
⚠️ 当使用 MiniMax 等模型作为底层 LLM 时，tool_call 的 arguments 必须是标准的 JSON 对象字符串。

禁止行为:
✗ arguments 返回数组格式（如 [{"key": "value"}]），必须是对象格式（如 {"key": "value"}）
✗ arguments 包含非法 JSON（如多余逗号、缺少引号等）
✗ arguments 为空字符串时直接回传给 API

如果检测到 tool_call arguments 格式异常：
1. 解析 arguments 字符串，如果是数组则提取第一个元素
2. 使用容错 JSON 解析器修复格式问题
3. 无法修复时跳过该 tool_call 并记录日志
```
