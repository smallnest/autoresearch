# Issue 选择策略

本文档定义如何从 GitHub 获取和筛选待处理的 Issues。

> 暂时本文件还没有使用，未来在自动化批量处理issue的时候才会使用。

---

## 获取 Issues

### API 调用

```bash
# 使用 gh 命令获取 Open Issues
gh issue list \
  --repo owner/repo \
  --state open \
  --limit 100 \
  --json number,title,labels,body,createdAt,updatedAt
```

### 过滤条件

```
必须满足:
- 状态为 Open
- 无排除标签
- 有明确的描述内容

可选过滤:
- 特定标签
- 特定作者
- 时间范围
```

---

## 排除规则

### 排除标签

以下标签的 Issue 不会被处理：

| 标签 | 原因 |
|------|------|
| `wontfix` | 已确认不修复 |
| `duplicate` | 重复的 Issue |
| `invalid` | 无效的 Issue |
| `blocked` | 被阻塞，等待其他条件 |
| `needs discussion` | 需要讨论 |
| `on hold` | 暂停处理 |
| `external` | 外部依赖问题 |
| `documentation` | 纯文档问题（可能不需要代码） |

### 排除条件

```
排除以下 Issue:
- 标题包含 "[WIP]" 或 "[DRAFT]"
- 正文包含 "DO NOT IMPLEMENT"
- 超过 6 个月未更新且无人评论
- 已有 PR 关联
- 标题或正文为空
```

---

## 优先级规则

### 标签权重

```yaml
priority_labels:
  critical:
    labels: ["priority: critical", "priority: p0", "urgent"]
    weight: 100

  high:
    labels: ["priority: high", "priority: p1"]
    weight: 50

  medium:
    labels: ["priority: medium", "priority: p2"]
    weight: 20

  low:
    labels: ["priority: low", "priority: p3"]
    weight: 10

  enhancement:
    labels: ["enhancement"]
    weight: 5

  default:
    weight: 15
```

### 类型权重

```yaml
type_labels:
  bug:
    labels: ["bug", "fix"]
    weight: 30

  feature:
    labels: ["feature", "enhancement"]
    weight: 20

  refactor:
    labels: ["refactor", "tech debt"]
    weight: 10

  test:
    labels: ["test", "testing"]
    weight: 5

  docs:
    labels: ["documentation", "docs"]
    weight: 3
```

### 时间因子

```yaml
time_factor:
  # 新 Issue (7天内) 获得加成
  new_issue_bonus: 10
  new_issue_days: 7

  # 长期未处理的 Issue 获得加成
  stale_issue_bonus: 15
  stale_issue_days: 30

  # 刚更新过的 Issue (有人评论) 获得加成
  recently_updated_bonus: 5
  recently_updated_days: 3
```

### 计算公式

```
优先级分数 = 基础权重
           + 标签权重 (最高匹配的优先级标签)
           + 类型权重 (最高匹配的类型标签)
           + 时间因子

示例:
Issue #42 标签: ["bug", "priority: high"]
创建于: 5 天前
最后更新: 2 天前

分数 = 15 (基础)
     + 50 (priority: high)
     + 30 (bug)
     + 10 (新 Issue)
     + 5 (刚更新)
     = 110
```

---

## 复杂度评估

### 评估维度

```yaml
complexity_indicators:
  simple:
    signals:
      - 标题包含 "fix", "typo", "update"
      - 正文少于 100 字
      - 无依赖关系
      - 单文件修改预期
    config:
      max_iterations: 3
      time_budget: 10m

  medium:
    signals:
      - 标题包含 "add", "implement", "refactor"
      - 正文 100-500 字
      - 涉及 2-3 个模块
      - 需要新增测试
    config:
      max_iterations: 5
      time_budget: 30m

  complex:
    signals:
      - 标题包含 "redesign", "migrate", "architecture"
      - 正文超过 500 字
      - 涉及多个模块
      - 需要设计决策
    config:
      max_iterations: 5
      time_budget: 60m
      requires_human_approval: true
```

### 评估流程

```
1. 分析 Issue 标题和正文
2. 识别关键词和信号
3. 评估涉及的代码范围
4. 判断是否需要设计决策
5. 分配复杂度等级和资源预算
```

---

## 选择策略

### 单次运行

```bash
# 处理单个指定 Issue
./autoresearch run --issue 42
```

选择逻辑：
1. 验证 Issue 存在且未被排除
2. 评估复杂度
3. 开始处理

### 批量运行

```bash
# 按优先级处理所有待处理 Issues
./autoresearch run --all

# 只处理特定标签
./autoresearch run --label "priority: high"

# 只处理 Bug 类型
./autoresearch run --label "bug"
```

选择逻辑：
1. 获取所有 Open Issues
2. 应用排除规则过滤
3. 计算每个 Issue 的优先级分数
4. 按分数降序排列
5. 从最高分开始处理
6. 每处理完一个 Issue 后重新评估列表

### 并行处理

```bash
# 并行处理多个 Issues（不推荐）
./autoresearch run --parallel 2 --all
```

注意：
- 并行处理可能导致资源竞争
- 建议只在 Issues 完全独立时使用
- 默认使用串行处理

---

## 处理顺序示例

假设有以下 Issues：

| Issue | 标题 | 标签 | 创建时间 | 最后更新 |
|-------|------|------|---------|---------|
| #50 | 修复登录Bug | bug, priority: high | 2天前 | 1天前 |
| #49 | 添加导出功能 | feature, priority: medium | 5天前 | 5天前 |
| #48 | 重构解析器 | refactor | 10天前 | 3天前 |
| #51 | 文档更新 | documentation | 1天前 | 1天前 |
| #47 | 优化性能 | enhancement, priority: low | 30天前 | 30天前 |

计算优先级分数：

| Issue | 计算 | 分数 |
|-------|------|------|
| #50 | 15 + 50 + 30 + 10 + 5 = 110 | 最高 |
| #49 | 15 + 20 + 20 + 10 + 0 = 65 | 第2 |
| #48 | 15 + 0 + 10 + 0 + 5 = 30 | 第4 |
| #51 | 15 + 0 + 3 + 10 + 5 = 33 | 第3 |
| #47 | 15 + 10 + 5 + 0 + 15 = 45 | 第5 |

处理顺序：#50 → #49 → #51 → #47 → #48

---

## Issue 验证

### 格式验证

```
必须包含:
- [ ] 标题（非空）
- [ ] 正文描述（非空）

建议包含:
- [ ] 重现步骤（Bug）
- [ ] 预期行为
- [ ] 实际行为
- [ ] 环境信息
```

### 质量评估

```
高质量 Issue:
- 描述清晰完整
- 有重现步骤
- 有预期结果
- 有合适的标签

低质量 Issue:
- 描述模糊
- 缺少关键信息
- 无法复现
- 标签不当
```

### 低质量处理

```
对于低质量 Issue:
1. 尝试理解核心诉求
2. 如果可以合理推断，继续处理
3. 如果无法理解，标记为 needs-context
4. 在日志中记录问题
```

---

## 更新频率

### 重新获取时机

```
每次运行开始时，重新获取 Issues 列表
每处理完一个 Issue 后，更新列表状态
如果遇到阻塞超过 10 分钟，刷新列表
```

### 缓存策略

```
不缓存 Issues 列表
始终使用最新数据
避免处理已关闭或已变更的 Issue
```

---

## 配置文件示例

```yaml
# autoresearch/config.yaml

issue_selector:
  # 排除配置
  exclude:
    labels:
      - wontfix
      - duplicate
      - invalid
      - blocked
      - "needs discussion"
    title_patterns:
      - "\\[WIP\\]"
      - "\\[DRAFT\\]"

  # 优先级配置
  priority:
    labels:
      critical: 100
      high: 50
      medium: 20
      low: 10
    types:
      bug: 30
      feature: 20
      refactor: 10
      test: 5
      docs: 3
    time:
      new_issue_bonus: 10
      new_issue_days: 7
      stale_bonus: 15
      stale_days: 30
      recent_update_bonus: 5
      recent_update_days: 3

  # 复杂度配置
  complexity:
    simple:
      max_iterations: 3
      time_budget: 10m
    medium:
      max_iterations: 5
      time_budget: 30m
    complex:
      max_iterations: 5
      time_budget: 60m
      requires_approval: true
```
