# 二次开发计划

## 目标

将当前仓库从“单个 GitHub Issue 自动处理器”升级为“可持续运行的自动化软件开发系统”，重点补齐以下能力：

- 从单 Issue 扩展到 Issue 队列调度
- 从自由文本评审扩展到结构化评审与更强 QA
- 从本地 runner 扩展到权限分离的自动收尾服务
- 从一次性执行扩展到可观测、可恢复、可审计的长期运行模式

---

## 当前基线

当前仓库已经具备这些可复用能力：

- 单 Issue 执行入口：`autoresearch/cli.py`
- 主流程编排：`autoresearch/runner.py`
- 纯逻辑层：agent 轮转、评分提取、错误检测、上下文溢出检测：`autoresearch/logic.py`
- UI 验证、dev server 管理、截图：`autoresearch/ui.py`
- 子任务机制：`tasks.json`
- 继续运行能力：基于 `.autoresearch/workflows/issue-*`
- 自动创建 PR / 合并 / 关闭 Issue

这意味着二次开发不需要重做主循环，应该在现有 runner 外围增加“调度层、QA 层、权限层”。

---

## 目标架构

建议把系统拆成 6 层：

1. `Spec / Intake`
- 输入来源包括 PRD、GitHub Issue、人工创建任务
- 输出统一任务模型：Issue、依赖、优先级、复杂度、验收标准

2. `Scheduling`
- 批量拉取 open issues
- 过滤不可执行任务
- 计算优先级
- 根据依赖关系决定下一批可执行任务

3. `Execution`
- 保留现有 planner / implement / review 主循环
- 支持单 Issue 模式与队列模式
- 支持 worker lease，避免多实例重复处理同一 Issue

4. `QA / Gate`
- Build / Lint / Test
- API / 合约测试
- E2E / UI 验证
- 安全扫描
- 结构化评审结果

5. `Privileged Actions`
- PR 创建
- Merge
- Issue comment / close
- Staging deploy
- Production release

6. `Observability`
- 每轮日志
- Issue 生命周期状态
- 关键指标
- 人工接管入口

---

## 研发原则

- 先增强确定性，再增加自治程度
- 高权限动作必须与代码生成解耦
- 批处理前先把单 Issue 成功率做稳
- 一切自动化都要可恢复、可中断、可审计
- 优先把“失败可解释”做好，而不是盲目扩大自动化范围

---

## 分阶段计划

## Phase 0：基线加固

目标：把当前单 Issue 模式打磨成稳定内核，为队列化做准备。

范围：

- 给 `runner.py` 拆出更清晰的子模块边界
- 把 GitHub CLI 调用封装成统一适配层
- 给现有流程补充更多单元测试和集成测试
- 增加结构化运行结果文件，而不只依赖日志文本

建议新增模块：

- `autoresearch/github.py`
- `autoresearch/gates.py`
- `autoresearch/progress.py`
- `autoresearch/tasks.py`

验收标准：

- 不改功能的前提下，`runner.py` 体量明显下降
- 单 Issue 主流程有可重复的测试覆盖
- 所有外部命令调用集中管理

---

## Phase 1：Issue 队列调度

目标：从“人工指定 Issue 编号”升级到“自动选择下一个可执行 Issue”。

范围：

- 将 `issue-selector.md` 真正接入代码
- 支持批量获取 open issues
- 支持标签过滤、复杂度评估、优先级打分
- 支持 `--next` / `--batch N` 模式

建议新增模块：

- `autoresearch/scheduler.py`
- `autoresearch/issue_selector.py`
- `autoresearch/queue_runner.py`

建议命令：

```bash
uv run python -m autoresearch.cli --next
uv run python -m autoresearch.cli --batch 3
uv run python -m autoresearch.cli --repo owner/repo --next
```

验收标准：

- 可以不指定 Issue 编号，自动选择候选 Issue
- 能跳过 `blocked` / `duplicate` / `wontfix` 等问题
- 能记录为什么选择了某个 Issue

---

## Phase 2：结构化评审与 QA 升级

目标：降低“自然语言评分”带来的随机性。

范围：

- 要求 reviewer 输出结构化 JSON，而不是只输出自然语言
- 审查结果包含：
  - `pass`
  - `score`
  - `findings`
  - `risk_level`
  - `required_fixes`
- 将 QA 门禁升级为分层：
  - unit
  - integration
  - e2e
  - UI
  - security

建议新增模块：

- `autoresearch/review_schema.py`
- `autoresearch/qa.py`

建议输出格式：

```json
{
  "pass": false,
  "score": 72,
  "riskLevel": "medium",
  "findings": [
    {
      "severity": "high",
      "summary": "API contract mismatch",
      "path": "src/api/user.ts"
    }
  ],
  "requiredFixes": [
    "Align response payload with existing contract",
    "Add regression tests for 404 branch"
  ]
}
```

验收标准：

- 审核分数不再依赖正则猜测
- runner 能区分“代码未通过”和“测试未通过”
- QA 失败能给出结构化反馈供下一轮修复

---

## Phase 3：PRD → Issue Intake

目标：把仓库从“Issue 执行器”升级到“需求进入系统后的完整入口”。

范围：

- 支持导入 PRD 文档
- 自动拆成候选 Issues
- 支持依赖关系、验收标准、优先级
- 自动写回 GitHub Issue

建议新增模块：

- `autoresearch/spec_parser.py`
- `autoresearch/issue_generator.py`

建议流程：

```text
PRD → stories → issues → dependency graph → queue scheduler → runner
```

验收标准：

- 能从一份 PRD 生成一组可执行 Issues
- 每个 Issue 都带有验收标准
- dependency 信息可被 scheduler 使用

---

## Phase 4：权限分离与人工审批

目标：避免把所有 GitHub / 部署权限直接交给 coding runner。

范围：

- 保留 runner 的代码修改权限
- 将 PR 创建、merge、close issue 提升为单独 action 层
- 引入人工审批点：
  - 高复杂度任务
  - 高风险目录
  - release / deploy

建议新增模块：

- `autoresearch/policy.py`
- `autoresearch/approval.py`
- `autoresearch/finalizer.py`

策略建议：

- `runner` 只负责产出变更和审核结果
- `finalizer` 根据策略决定：
  - 自动 merge
  - 创建 PR 等待人工审批
  - 阻止继续执行

验收标准：

- 高风险任务不会被自动 merge
- 合并策略可配置
- 关键动作都有审计记录

---

## Phase 5：长期运行模式

目标：让系统能作为“持续开发 worker”运行，而不是一次性命令。

范围：

- daemon / cron / CI 驱动运行
- worker lease / heartbeat
- 队列状态面板
- 失败重试策略
- 每日运行报告

建议新增模块：

- `autoresearch/daemon.py`
- `autoresearch/telemetry.py`
- `autoresearch/reporting.py`

验收标准：

- 支持连续处理多个 Issue
- 不会多个 worker 抢同一个 Issue
- 有清晰的运行报告与失败汇总

---

## 建议的优先级

优先顺序不要按“概念酷炫”排，而要按“提升自动完成率”排：

1. Phase 0：基线加固
2. Phase 2：结构化评审与 QA 升级
3. Phase 1：Issue 队列调度
4. Phase 4：权限分离与审批
5. Phase 3：PRD → Issue Intake
6. Phase 5：长期运行模式

原因：

- 先把单 Issue 成功率做稳
- 再把评审误判率降下来
- 然后再扩大任务来源和并发范围

---

## 建议的代码落点

基于当前目录结构，建议这样扩展：

```text
autoresearch/
├── cli.py
├── runner.py
├── logic.py
├── ui.py
├── github.py            # 新增：GitHub 访问与写回
├── tasks.py             # 新增：tasks.json 读写与状态推进
├── progress.py          # 新增：progress.md 与结构化运行记录
├── gates.py             # 新增：build/lint/test/e2e/security
├── scheduler.py         # 新增：Issue 选择与批处理
├── qa.py                # 新增：结构化 QA 输出
├── policy.py            # 新增：自动 merge / 审批策略
├── finalizer.py         # 新增：PR / merge / close 封装
└── telemetry.py         # 新增：指标与报告
```

---

## 里程碑定义

### M1：稳定单 Issue 自动开发

完成标志：

- 单 Issue 成功率可稳定复现
- 所有核心逻辑已有 Python 测试
- 结构化评审落地

### M2：自动选择下一个 Issue

完成标志：

- 可自动从 repo 中选择下一个可执行 Issue
- 支持批量处理
- 支持复杂度分级

### M3：端到端自动开发流水线

完成标志：

- 可从 PRD 生成 Issues
- 可自动排队执行
- 可根据策略自动 merge 或人工审批

---

## 指标体系

建议从一开始就记录这些指标：

- Issue 自动完成率
- 首轮通过率
- 平均迭代轮数
- 平均处理时长
- QA 失败率
- 自动 merge 率
- 人工接管率
- 误通过率

这些指标可以先写进 `.autoresearch/metrics.jsonl`，后续再接看板。

---

## 建议拆成的首批开发任务

建议先按 8 个 Issue 来推进二次开发：

1. 抽离 GitHub 访问层，替代 runner 中分散的 gh 调用
2. 抽离 tasks / progress 管理层，降低 runner 复杂度
3. 引入结构化 reviewer 输出 JSON schema
4. 将 hard gate 升级为可配置 QA pipeline
5. 落地 issue-selector，支持 `--next`
6. 增加 batch 模式与队列日志
7. 引入 merge policy 与人工审批策略
8. 增加 metrics / report 输出

---

## 下一步建议

如果现在就进入二次开发，建议下一步直接做两件事：

1. 先把 `runner.py` 拆分成 `github.py + tasks.py + progress.py + gates.py`
2. 再实现结构化 reviewer 输出，替代当前分数正则解析

这样做能最快提升代码可维护性和自动化稳定性，并且不会破坏现有单 Issue 闭环。
