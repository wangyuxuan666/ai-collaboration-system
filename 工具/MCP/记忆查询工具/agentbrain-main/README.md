# agentbrain

> Local-first long-term memory for AI agents — a plain Markdown vault + a thin MCP server.
> 给 AI Agent 用的本地长期记忆：纯 Markdown 知识库 + 薄 MCP server。

[中文快速上手](#中文快速上手) · [English quickstart](#english-quickstart)

## Why agentbrain / 设计理念

- **Plain Markdown, no lock-in** — your memory is a folder of `.md` files. Open it in
  Obsidian, grep it, version it with Git. Remove agentbrain and the memory stays.
- **Token-efficient by design** — index-first retrieval: `Index.md` is the cheap first
  layer, BM25 (CJK-aware) only ranks candidates, and query output is compact by
  default (`mode='index'`); full text only on demand.
- **Traceable revisions** — agents create lessons and revise the same stable id through
  tools; revision history stays in the lesson. Consolidation still requires approval.
- **Plug-and-play via MCP** — one server, every client: Claude Code, Codex CLI,
  OpenCode, Cursor, DSH, Open WebUI, ...
- **Secrets never enter the vault** — credentials live in env/keyring; lessons reference
  `${ENV:VAR_NAME}` placeholders only, resolved at runtime via shell.

## Vault layout

```
agentbrain/                    # vault root (git-friendly, Obsidian-friendly)
├─ AGENTS.md                     # rules every agent reads at session start
├─ Case-Learnings/
│  ├─ Index.md                   # auto-generated lesson index (retrieval layer 1)
│  ├─ log.md                     # append-only audit log
│  ├─ Learnings/                 # one lesson per file, YAML frontmatter
│  │  └─ case-001-lesson-01.md   # 文件名 = {case_id}-lesson-{NN}，自动生成
│  └─ _consolidations/           # merge/promotion proposals (human approval)
└─ Agent-Profile/
   ├─ Immutable/                 # stable facts maintained by the owner
   ├─ Mutable-Hints/             # active global preferences, tool-maintained
   ├─ _suggestions/              # pending/applied/rejected preference proposals
   └─ _history/                  # tool-maintained profile history
```

## 中文快速上手

```bash
pip install -e .                 # 需要 Python >= 3.10
agentbrain init ~/agentbrain     # 生成 vault 脚手架（幂等，可重复执行）
agentbrain ingest --case demo --lesson "部署前必须先跑迁移脚本" --tags 部署,运维
agentbrain query "部署 迁移"
agentbrain feedback demo-lesson-01 --result correct --effect "按经验修改了部署动作" --evidence "部署验收通过"
agentbrain profile                # 查看固定信息与当前生效的全局偏好
agentbrain profile-set --key "回复语言" --value "中文" --reason "用户明确要求"
agentbrain profile-suggest --key "默认回答" --value "简短直接" --reason "AI 根据多次行为推测"
agentbrain profile-apply <suggestion_id>   # 用户确认候选后生效
agentbrain profile-remove --key "默认回答" --reason "用户确认删除"
agentbrain lint                    # 体检：重复/过时/无标签/低置信度 → 生成整合提案
agentbrain apply lint-20260820-172206.md   # 人工审核后执行提案（自动归档）
agentbrain distill                 # 分析 log 中重复出现的模式 → 生成提升提案
```

在 MCP 客户端里接入（以 Claude Code 为例）：

```bash
claude mcp add agentbrain -- agentbrain serve
```

通用 MCP JSON 配置（Cursor / Open WebUI 等）：

```json
{
  "mcpServers": {
    "agentbrain": {
      "command": "agentbrain",
      "args": ["serve"],
      "env": { "AGENTBRAIN_VAULT": "D:\\agentbrain" }
    }
  }
}
```

Vault 路径解析顺序：`--vault` 参数 > `AGENTBRAIN_VAULT` 环境变量 > `~/agentbrain`。

## English quickstart

```bash
pip install -e .                 # Python >= 3.10
agentbrain init ~/agentbrain     # scaffold the vault (idempotent)
agentbrain ingest --case demo --lesson "Always run migrations before deploy" --tags deploy,ops
agentbrain query "deploy migrations"
agentbrain profile                # print the owner profile
agentbrain profile-set --key "Reply language" --value "English" --reason "Explicit owner instruction"
agentbrain profile-suggest --key "Answer length" --value "Keep answers under 3 sentences." --reason "Inferred pattern"
agentbrain profile-apply <suggestion_id>   # apply after owner confirmation
agentbrain profile-remove --key "Answer length" --reason "Owner confirmed removal"
agentbrain lint                    # health check → consolidation proposals
agentbrain apply lint-20260820-172206.md   # execute an approved proposal (archives it)
agentbrain distill                 # recurring-pattern analysis → promotion proposals
agentbrain serve                   # start the MCP server on stdio
```

Codex CLI (`~/.codex/config.toml`):

```toml
[mcp_servers.agentbrain]
command = "agentbrain"
args = ["serve"]
```

## MCP tools

| Tool | Purpose |
|------|---------|
| `memory_query(query, top_k=5, mode="index")` | Search lessons. `mode='index'` returns compact hits (id, summary, tags, path, gist); `mode='full'` adds full text. |
| `memory_ingest(case_id, lesson, tags, confidence=0.5, source_summary=None)` | Save an unverified three-section lesson; refuses secrets and clamps confidence to 0.1–1.0. |
| `memory_history(lesson_id)` | Read the stable lesson's revision history before correction. |
| `memory_revise(lesson_id, lesson, change, reason, ...)` | Revise while preserving id/history; enforces the same structure, secret and confidence checks as ingest. |
| `memory_feedback(lesson_id, result, effect, evidence)` | Record `correct` or `wrong` only when the lesson changed an action and that action has outcome evidence. |
| `memory_lint(scope="all")` | Health check: duplicates, stale, expired, untagged, low-confidence. Writes a merge proposal to `_consolidations/`. |
| `memory_consolidation_apply(proposal)` | Applies an owner-approved Lesson merge proposal; superseded files and history remain archived. |
| `memory_distill(window_days=30, min_repeat=3)` | Finds cases/tags with ≥ N accepted uses in the window and writes a promotion proposal. |
| `memory_profile()` | Returns stable owner facts and active global preferences. Read-only; call once per session. |
| `memory_profile_set(key, value, reason)` | Adds an explicit global preference; refuses to overwrite an existing field. |
| `memory_profile_suggest(key, value, reason)` | Creates a pending new/change proposal with the current and proposed values. |
| `memory_profile_apply(suggestion_id)` | Applies a pending suggestion after owner confirmation. |
| `memory_profile_reject(suggestion_id, reason)` | Rejects a pending suggestion after owner decision. |
| `memory_profile_remove(key, reason)` | Removes an existing field after its current value was shown and the owner confirmed. |
| `memory_profile_history(key="")` | Returns all profile history or the history for one key. |
| `memory_suggest(title, change)` | Backward-compatible alias for `memory_profile_suggest`. |

## MCP resources

| URI | Content |
|-----|---------|
| `agentbrain://rules` | `AGENTS.md` — vault rules for every agent |
| `agentbrain://index` | `Case-Learnings/Index.md` — retrieval layer 1 |
| `agentbrain://profile` | merged owner profile (read-only) |

Agents are expected to follow `AGENTS.md` in the vault root: read the profile once,
maintain global preferences through Profile tools, query before action, ingest new lessons,
revise existing lessons through tools, record feedback only after actual use, and never write secrets. Consolidation proposals carry
machine-readable directive blocks (```` ```agentbrain ````); only the owner
executes them via `agentbrain apply`.

## Design notes

- **Retrieval scoring**: BM25 over summary (×3), tags (×2), case id and body, with a
  CJK bigram tokenizer so Chinese queries work out of the box; results are boosted by
  `verified`, `use_count` and recent `last_verified_at`, demoted when stale (> 1 year).
- **Self-maintenance signals**: query does not count as use; accepted feedback increments
  `use_count` and feeds `memory_distill`; `lint` changes nothing silently —
  every mutation of history goes through human-approved proposals.
- **Single-user, local-first**: no daemon, no ports; concurrent writes from several
  agents are serialized by a transient `.vault.lock` (auto-cleaned, stale-reclaimed
  after 60 s), and all file writes are atomic (temp + rename) so readers never see
  torn files.

## Changelog

- **0.4.0** — Two-layer profile/lesson workflow; BOM-compatible reads; unverified
  lessons default to confidence 0.5; query no longer counts as use; actual outcomes
  are recorded through `memory_feedback`; revisions preserve all prior history;
  distillation is based on accepted uses; legacy query counters can be migrated.
- **0.3.1** — Data-integrity fixes: concurrent same-case ingests no longer overwrite
  each other (lesson-id allocation moved inside the vault lock); `confidence: 0.0`
  round-trips correctly (was silently coerced to 0.8); lint/distill proposals are
  written atomically under the lock with collision-free names; merge proposals now
  keep the more-used lesson as the keeper; duplicate detection pre-tokenizes (O(n²)
  without re-tokenizing per pair). Session wrap-up rule added to AGENTS.md. 59 tests.
- **0.3.0** — Concurrency & robustness: cross-process/thread vault write lock
  (`.vault.lock`, re-entrant, stale-reclaim), atomic writes (temp + rename),
  `apply` is now a single transaction; query no longer rebuilds the index once per
  hit (one rebuild per query); stray non-lesson `.md` files in `Learnings/` are
  ignored; `confidence` clamped to [0,1]; unknown `mode` falls back to `index`;
  same-second suggestions no longer overwrite each other. 54 tests.
- **0.2.0** — Owner profile layer (`memory_profile` / `memory_suggest` + MCP
  resources), lint/distill proposals with machine-readable directive blocks,
  `agentbrain apply` with cycle/self-supersede/dangling checks.
- **0.1.0** — Initial MVP: vault + frontmatter + CJK-aware BM25 retrieval,
  MCP server (query/ingest/lint/distill) + CLI, scaffold templates.

## Roadmap

- [ ] Hybrid fallback search (SQLite FTS5 + local embedding, RRF fusion) for large vaults
- [x] `agentbrain apply <proposal>` to execute approved consolidations
- [x] Owner profile layer: `memory_profile` / `memory_suggest` + MCP resources
- [ ] Temp-layer bridge (Mem0-style short-term memory → distill promotions)
- [ ] Keyring-backed `${ENV:...}` resolution helper
- [ ] Git snapshot hook on ingest/distill

## Development

```bash
pip install -e ".[dev]"
pytest
```

## License

Apache-2.0 — see [LICENSE](LICENSE).
