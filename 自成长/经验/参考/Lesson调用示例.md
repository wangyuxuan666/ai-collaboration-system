---
所属: 自成长
必读: 参考
---

# Lesson 调用示例

## 新增

```text
memory_ingest(
  case_id: "文档产出",
  lesson: "## 经验教训\n\n内部交接文档只保留会影响接收者行动的内容。\n\n## 适用场景\n\n编写内部交接文档时。\n\n## 规避方案\n\n删除不影响后续行动的背景和讨论过程。",
  tags: ["文档产出", "交接文档"],
  confidence: 0.9,
  source_summary: "内部交接文档只保留影响接收者行动的内容"
)
```

## 修正

```text
memory_revise(
  lesson_id: "文档产出-lesson-01",
  lesson: "## 经验教训\n\n文档只保留对接收者有用的内容。\n\n## 适用场景\n\n编写内部交接文档时。\n\n## 规避方案\n\n不堆砌背景和无关内容。",
  change: "补充适用边界并精简规避方案",
  reason: "用户明确了该偏好只适用于内部交接文档",
  confidence: 0.5,
  tags: ["文档产出", "交接文档"]
)
```

## 反馈

```text
memory_feedback(
  lesson_id: "文档产出-lesson-01",
  result: "correct",
  effect: "按经验删除了不影响接收者行动的背景内容",
  evidence: "修改后的交接文档通过接收者验收"
)
```
