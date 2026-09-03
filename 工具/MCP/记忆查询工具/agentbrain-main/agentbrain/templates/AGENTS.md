# agentbrain vault rules

## Memory layers

- `Agent-Profile/` contains small, stable facts and preferences that apply to every task. Read it once per session with `memory_profile`.
- `Case-Learnings/Learnings/` contains contextual lessons. Search them before action with `memory_query`; do not load all lessons.
- Keep one active source for the same meaning. A specific lesson overrides a global profile default.

## Lesson lifecycle

1. Query is retrieval only. It does not count as use.
2. Add a genuinely new lesson with `memory_ingest`; new lessons start unverified.
3. Correct an existing lesson by calling `memory_history` and then `memory_revise`. Keep its stable id and history.
4. After a lesson changes an action, call `memory_feedback` with the concrete effect and outcome evidence. Query hits or task success alone do not count as use.
5. Before consolidating duplicate lessons, show the proposal to the owner. Call `memory_consolidation_apply` only after confirmation; it supersedes rather than deletes history.
6. Never edit lesson, index or log files by hand. Use the tools.

## Profile lifecycle

1. Use `memory_profile_set` only for an explicit global preference with no existing equivalent field.
2. Before changing an existing preference, read `memory_profile_history`, create a suggestion, show the old value, proposed value and reason, then ask the owner. Apply or reject only after that decision.
3. Before removing a preference, show its current value and ask the owner; call `memory_profile_remove` only after confirmation.
4. Inferred preferences always start as suggestions. Never edit active Profile files directly.

## Storage

| Path | Purpose |
|---|---|
| `Case-Learnings/Index.md` | Generated compact lesson index |
| `Case-Learnings/Learnings/*.md` | Current lesson content and revision history |
| `Case-Learnings/log.md` | Tool-maintained audit log |
| `Case-Learnings/_consolidations/` | Maintenance proposals requiring review |
| `Agent-Profile/Immutable/` | Stable facts maintained by the owner |
| `Agent-Profile/Mutable-Hints/preferences.md` | Active global preferences maintained by Profile tools |
| `Agent-Profile/_suggestions/` | Pending, applied and rejected preference suggestions |
| `Agent-Profile/_history/log.md` | Profile change history maintained by Profile tools |

Never store passwords, tokens, private keys, API keys or other directly usable secrets in the vault. Keep summaries short and specific enough for retrieval.
