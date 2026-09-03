from __future__ import annotations

import datetime as dt
import re
from collections import Counter
from pathlib import Path

from .config import Config
from .frontmatter import parse
from .locking import atomic_write
from .models import Lesson
from .profile import Profile
from .retrieval import _days_since, search_lessons, tokenize
from .vault import Vault, VaultNotInitialized

_SUMMARY_CHARS = 160
_UNSAFE_CASE = re.compile(r'[\\/:*?"<>|\s]+')
_LESSON_HEADING = re.compile(
    r"^#{1,6}\s*(经验教训(?:（[^）]*）|\([^)]*\))?|适用场景|规避方案)\s*$",
    re.MULTILINE,
)
_LESSON_SECTIONS = ("经验教训", "适用场景", "规避方案")
_SENSITIVE_PATTERNS = (
    ("private key", re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----")),
    ("API token", re.compile(r"\bsk-[A-Za-z0-9_-]{16,}\b")),
    ("GitHub token", re.compile(r"\bgh[pousr]_[A-Za-z0-9]{20,}\b")),
    ("AWS access key", re.compile(r"\bAKIA[0-9A-Z]{16}\b")),
    (
        "assigned secret",
        re.compile(
            r"(?:password|passwd|pwd|token|api[_ -]?key|secret|密码|令牌|密钥)"
            r"\s*[:=：]\s*[\"']?(?!<|\*|x{3,}|redacted\b|example\b|示例\b)"
            r"[^\s\"']{4,}",
            re.IGNORECASE,
        ),
    ),
)


def _open_vault(vault: Vault | None) -> Vault:
    return vault if vault is not None else Vault.open(Config.load())


def _oneline(text: str, n: int) -> str:
    s = " ".join((text or "").split())
    return s[: n - 1] + "…" if len(s) > n else s


def _clean_case_id(case_id: str) -> str:
    cid = _UNSAFE_CASE.sub("-", (case_id or "").strip())
    return cid or "misc"


def _normalize_tags(tags) -> list[str]:
    if tags is None:
        return []
    if isinstance(tags, str):
        tags = tags.split(",")
    out: list[str] = []
    for t in tags:
        t = str(t).strip().strip("#")
        if t and t not in out:
            out.append(t)
    return out[:8]


def _sensitive_kind(*values: object) -> str | None:
    text = "\n".join(str(value) for value in values if value is not None)
    for kind, pattern in _SENSITIVE_PATTERNS:
        if pattern.search(text):
            return kind
    return None


def _lesson_structure_error(lesson: str) -> str | None:
    matches = list(_LESSON_HEADING.finditer(lesson))
    names = [
        "经验教训" if match.group(1).startswith("经验教训") else match.group(1)
        for match in matches
    ]
    if names != list(_LESSON_SECTIONS):
        return (
            "lesson must contain exactly these non-empty sections in order: "
            "经验教训, 适用场景, 规避方案."
        )
    for index, match in enumerate(matches):
        end = matches[index + 1].start() if index + 1 < len(matches) else len(lesson)
        if not lesson[match.end():end].strip():
            return f"lesson section '{names[index]}' must not be empty."
    return None


def _validate_lesson_write(lesson: str, *metadata: object) -> str | None:
    sensitive = _sensitive_kind(lesson, *metadata)
    if sensitive:
        return f"Refused: suspected sensitive value ({sensitive}); store only its location or handling rule."
    structure_error = _lesson_structure_error(lesson)
    if structure_error:
        return f"Refused: {structure_error}"
    return None


def _stamp() -> str:
    return dt.datetime.now().strftime("%Y%m%d-%H%M%S")


def _next_proposal_path(v: Vault, kind: str) -> Path:
    v.consolidations_dir.mkdir(parents=True, exist_ok=True)
    stamp = _stamp()
    path = v.consolidations_dir / f"{kind}-{stamp}.md"
    n = 2
    while path.exists():  # same-second runs must not clobber each other
        path = v.consolidations_dir / f"{kind}-{stamp}-{n}.md"
        n += 1
    return path


def _jaccard(a: set, b: set) -> float:
    if not a or not b:
        return 0.0
    return len(a & b) / len(a | b)


_QUERY_MODES = ("index", "full")


def memory_query(
    query: str,
    top_k: int = 5,
    mode: str = "index",
    vault: Vault | None = None,
) -> str:
    try:
        v = _open_vault(vault)
    except VaultNotInitialized as e:
        return str(e)

    if mode not in _QUERY_MODES:
        mode = "index"
    # strip the revision-history section so retrieval & display see only current content
    lessons = v.lessons()
    for l in lessons:
        l.content = v.content_without_history(l)
    ranked = search_lessons(lessons, query)
    hits = ranked[: max(1, top_k)]
    if not hits:
        return (
            "No lessons matched. If this task produces a reusable lesson, "
            "call memory_ingest when done."
        )

    lines = [f"{len(hits)} lesson(s) matched (mode={mode}):", ""]
    for rank, (l, _score) in enumerate(hits, 1):
        lines.append(
            f"{rank}. [{l.lesson_id}] {l.source_summary} "
            f"(conf {l.confidence} · used {l.use_count} · {l.last_verified_at})"
        )
        lines.append(f"   tags: {', '.join(l.tags) or '-'}")
        lines.append(f"   path: {v.relpath(l.path)}")
        lines.append(f"   gist: {_oneline(l.content, _SUMMARY_CHARS)}")
        if mode == "full":
            lines.extend(["", l.content.strip(), ""])
    return "\n".join(lines)


def memory_ingest(
    case_id: str,
    lesson: str,
    tags: list[str] | None = None,
    confidence: float = 0.5,
    source_summary: str | None = None,
    vault: Vault | None = None,
) -> str:
    try:
        v = _open_vault(vault)
    except VaultNotInitialized as e:
        return str(e)
    if not lesson or not lesson.strip():
        return "Refused: empty lesson."

    validation_error = _validate_lesson_write(
        lesson, case_id, source_summary, *(_normalize_tags(tags))
    )
    if validation_error:
        return validation_error

    tags = _normalize_tags(tags)
    case_id = _clean_case_id(case_id)
    confidence = min(1.0, max(0.1, confidence))

    with v.locked():  # id allocation + write must be atomic: parallel ingests of
        # the same case would otherwise draw the same lesson_id and overwrite
        lesson_obj = v.new_lesson(
            case_id=case_id,
            source_summary=(source_summary or "").strip() or _oneline(lesson, 60),
            content=lesson.strip(),
            tags=tags,
            confidence=confidence,
        )
        v._save_locked(lesson_obj, action="ingest")

    # --- post-save duplicate hint: the lesson is already saved; we now search
    # for possibly-similar lessons (excluding the lesson just written) and
    # remind the user, letting them decide whether to merge (revise) or keep
    # both. Never silently delete. ---
    hint = ""
    existing = [
        l for l in v.lessons()
        if not l.superseded_by and l.lesson_id != lesson_obj.lesson_id
    ]
    if existing:
        query_text = " ".join(
            [lesson_obj.source_summary, lesson_obj.content]
        )
        ranked = search_lessons(existing, query_text)
        if ranked:
            top, score = ranked[0]
            if top.case_id == case_id:
                hint = (
                    f"\nNote: possibly similar to existing [{top.lesson_id}] "
                    f"{top.source_summary} (conf {top.confidence}, used {top.use_count}).\n"
                    f"If it is a duplicate, decide with the user: keep both, or revise "
                    f"one into the other via memory_revise."
                )

    return (
        f"Saved {lesson_obj.lesson_id} → {v.relpath(lesson_obj.path)}\n"
        f"tags: {', '.join(tags) or '-'} · confidence {confidence} · index & log updated"
        f"{hint}"
    )


def memory_revise(
    lesson_id: str,
    lesson: str,
    change: str,
    reason: str,
    confidence: float | None = None,
    source_summary: str | None = None,
    tags: list[str] | None = None,
    vault: Vault | None = None,
) -> str:
    """Revise an existing lesson in place: update its current content and append
    a revision-history row (time / what changed / why). The lesson id stays the
    same; history accumulates inside the same file (growth, not replacement)."""
    try:
        v = _open_vault(vault)
    except VaultNotInitialized as e:
        return str(e)
    if not lesson_id or not lesson_id.strip():
        return "Refused: empty lesson_id."
    if not lesson or not lesson.strip():
        return "Refused: empty lesson content."
    if not change or not change.strip():
        return "Refused: change (what changed) is required."

    validation_error = _validate_lesson_write(
        lesson, change, reason, source_summary, *(_normalize_tags(tags))
    )
    if validation_error:
        return validation_error

    existing = v.get(lesson_id)
    if existing is None:
        return (
            f"Lesson not found: {lesson_id}. Use memory_ingest to create a new lesson, "
            f"or memory_query first to find the right id."
        )

    new_conf = min(1.0, max(0.1, confidence)) if confidence is not None else None
    # if no explicit summary given, derive it from the new content (like ingest)
    new_summary = (
        source_summary.strip() if source_summary is not None else existing.source_summary
    ) or _oneline(lesson, 60)
    new_tags = _normalize_tags(tags) if tags is not None else existing.tags
    existing.source_summary = new_summary
    existing.tags = new_tags
    today = dt.date.today().strftime("%Y-%m-%d")
    v.apply_revision(
        existing,
        new_content=lesson.strip(),
        change=change.strip(),
        reason=(reason or "").strip(),
        today=today,
        confidence=new_conf,
    )
    return (
        f"Revised {existing.lesson_id} → v{existing.revision} "
        f"(conf {existing.confidence}). History appended; id unchanged."
    )


def memory_feedback(
    lesson_id: str,
    result: str,
    effect: str,
    evidence: str,
    vault: Vault | None = None,
) -> str:
    """Record an outcome only when a lesson changed action and has evidence."""
    try:
        v = _open_vault(vault)
    except VaultNotInitialized as e:
        return str(e)
    result = (result or "").strip().lower()
    if result not in ("correct", "wrong"):
        return "Refused: result must be 'correct' or 'wrong'."
    effect = _oneline(effect, 500)
    evidence = _oneline(evidence, 500)
    if not effect:
        return "Refused: effect is required; a query hit alone is not usage."
    if not evidence:
        return "Refused: evidence is required before feedback changes counts."
    lesson = v.get((lesson_id or "").strip())
    if lesson is None:
        return f"Lesson not found: {lesson_id}"
    v.record_feedback(lesson, result, f"effect={effect}; evidence={evidence}")
    label = "accepted" if result == "correct" else "rejected"
    return (
        f"Feedback {label}: {lesson.lesson_id} · conf {lesson.confidence} · "
        f"used {lesson.use_count} · failed {lesson.failure_count}"
    )


def memory_history(lesson_id: str, vault: Vault | None = None) -> str:
    """Return the full revision history of one lesson by its stable id.
    Used right before revising: the AI reads the history to spot patterns
    (e.g. flipping back and forth) and decide whether/how to revise."""
    try:
        v = _open_vault(vault)
    except VaultNotInitialized as e:
        return str(e)
    if not lesson_id or not lesson_id.strip():
        return "Refused: empty lesson_id."

    lesson = v.get(lesson_id)
    if lesson is None:
        return f"Lesson not found: {lesson_id}"

    rows = v.history_rows(lesson)
    if not rows:
        return (
            f"[{lesson.lesson_id}] no revision history yet (v1). "
            f"Current: {lesson.source_summary} (conf {lesson.confidence}, used {lesson.use_count})."
        )
    header = "| 版本 | 时间 | 动作 | 原因 |\n|---|---|---|---|"
    return (
        f"[{lesson.lesson_id}] revision history (current v{lesson.revision}):\n\n"
        f"{header}\n" + "\n".join(rows) +
        f"\n\nCurrent: {lesson.source_summary} (conf {lesson.confidence}, used {lesson.use_count})"
    )


def _similar(a: Lesson, b: Lesson) -> bool:
    if _jaccard(set(tokenize(a.source_summary)), set(tokenize(b.source_summary))) >= 0.6:
        return True
    tags_sim = _jaccard(set(a.tags), set(b.tags))
    content_sim = _jaccard(set(tokenize(a.content)), set(tokenize(b.content)))
    return tags_sim >= 0.5 and content_sim >= 0.4


def _similar_pre(
    sa: set, ta: set, ca: set, sb: set, tb: set, cb: set
) -> bool:
    if _jaccard(sa, sb) >= 0.6:
        return True
    return _jaccard(ta, tb) >= 0.5 and _jaccard(ca, cb) >= 0.4


def _dup_similar(new_summary: str, new_tags: list[str], new_content: str,
                 l_summary: str, l_tags: list[str], l_content: str) -> bool:
    """Source-level duplicate heuristic used by memory_ingest.
    Looser than lint's _similar_pre on purpose: when writing, better to ask
    the user than to silently save a near-duplicate."""
    s = _jaccard(set(tokenize(new_summary)), set(tokenize(l_summary)))
    t = _jaccard(set(tokenize(" ".join(new_tags))), set(tokenize(" ".join(l_tags))))
    c = _jaccard(set(tokenize(new_content)), set(tokenize(l_content)))
    if s >= 0.5:
        return True
    if t >= 0.5 and c >= 0.3:
        return True
    if c >= 0.6:
        return True
    return False


def memory_lint(scope: str = "all", vault: Vault | None = None) -> str:
    try:
        v = _open_vault(vault)
    except VaultNotInitialized as e:
        return str(e)

    lessons = v.lessons(include_superseded=True)
    if scope.startswith("tag:"):
        target = scope[4:].strip()
        lessons = [l for l in lessons if target in l.tags]
    if not lessons:
        return "No lessons in scope."

    findings: list[str] = []
    duplicate_pairs: list[tuple[Lesson, Lesson]] = []
    by_id = {l.lesson_id: l for l in lessons}
    active = [l for l in lessons if not l.superseded_by]

    pre = [
        (l, set(tokenize(l.source_summary)), set(l.tags), set(tokenize(l.content)))
        for l in active
    ]
    for i, (a, sa, ta, ca) in enumerate(pre):
        for b, sb, tb, cb in pre[i + 1 :]:
            if _similar_pre(sa, ta, ca, sb, tb, cb):
                findings.append(f"DUPLICATE {a.lesson_id} ≈ {b.lesson_id}")
                duplicate_pairs.append((a, b))

    for l in lessons:
        d = _days_since(l.last_verified_at or l.created_at)
        if d is not None and d > 90 and not l.superseded_by:
            findings.append(f"STALE {l.lesson_id} (last verified {d} days ago)")
        exp = _days_since(l.valid_until)
        if l.valid_until and exp is not None and exp >= 0:
            findings.append(f"EXPIRED {l.lesson_id} (valid_until {l.valid_until})")
        if not l.tags:
            findings.append(f"ORPHAN {l.lesson_id} (no tags)")
        if l.confidence < 0.5:
            findings.append(f"LOWCONF {l.lesson_id} (confidence {l.confidence})")
        if l.superseded_by and l.superseded_by not in by_id:
            findings.append(f"DANGLING {l.lesson_id} → missing {l.superseded_by}")

    if not findings:
        return "Lint clean: no duplicates, no stale/expired/orphan/low-confidence lessons."

    findings.sort()

    # Collapse overlapping duplicate pairs into groups so one lint proposal can
    # never suggest conflicting or cyclic supersede directives.
    groups: list[set[str]] = []
    for a, b in duplicate_pairs:
        connected = [g for g in groups if a.lesson_id in g or b.lesson_id in g]
        if not connected:
            groups.append({a.lesson_id, b.lesson_id})
            continue
        merged = {a.lesson_id, b.lesson_id}
        for group in connected:
            merged.update(group)
            groups.remove(group)
        groups.append(merged)

    directives: list[tuple[str, str]] = []
    for group in groups:
        members = [by_id[lesson_id] for lesson_id in sorted(group)]
        keeper = max(members, key=lambda lesson: lesson.use_count)
        directives.extend(
            (lesson.lesson_id, keeper.lesson_id)
            for lesson in members
            if lesson.lesson_id != keeper.lesson_id
        )

    proposal_lines = [
        "# Lint proposal — auto-generated",
        "",
        "Review required. This file does not change any lesson by itself.",
        "",
        "## Findings",
        "",
        *[f"- {finding}" for finding in findings],
    ]
    if directives:
        proposal_lines += [
            "",
            "## Suggested merges",
            "",
            "The target is the most-used lesson in each duplicate group.",
            "",
            "```agentbrain",
            *[f"supersede: {old} -> {new}" for old, new in directives],
            "```",
        ]

    with v.locked():
        proposal_path = _next_proposal_path(v, "lint")
        atomic_write(proposal_path, "\n".join(proposal_lines) + "\n")
        v._append_log_locked("lint", f"findings:{len(findings)}")

    return "\n".join(
        [f"Lint found {len(findings)} issue(s); nothing was changed:", ""]
        + [f"- {finding}" for finding in findings]
        + [
            "",
            f"Proposal written: {v.relpath(proposal_path)}",
            "Owner review is required before apply.",
        ]
    )


def memory_consolidation_apply(
    proposal: str, vault: Vault | None = None
) -> str:
    """Apply an owner-approved Lesson consolidation proposal."""
    try:
        v = _open_vault(vault)
    except VaultNotInitialized as e:
        return str(e)
    from .apply import ProposalError, apply_proposal

    try:
        return apply_proposal(v, proposal)
    except ProposalError as e:
        return f"Refused: {e}"


def memory_distill(
    window_days: int = 30,
    min_repeat: int = 3,
    vault: Vault | None = None,
) -> str:
    try:
        v = _open_vault(vault)
    except VaultNotInitialized as e:
        return str(e)

    cutoff = (dt.date.today() - dt.timedelta(days=window_days)).isoformat()
    entries = [
        e for e in v.log_entries()
        if e["date"] >= cutoff and e["action"] == "feedback-correct"
    ]

    case_counts: Counter[str] = Counter()
    tag_counts: Counter[str] = Counter()
    for e in entries:
        lesson = v.get(e["object"])
        if lesson is None:
            continue
        case_counts[lesson.case_id] += 1
        for t in lesson.tags:
            tag_counts[t] += 1

    hot_cases = sorted((c, n) for c, n in case_counts.items() if c and n >= min_repeat)
    hot_tags = sorted((t, n) for t, n in tag_counts.items() if n >= min_repeat)
    if not hot_cases and not hot_tags:
        return (
            f"No recurring successful uses in the last {window_days} days "
            f"(threshold: {min_repeat}). Nothing to distill."
        )

    lines = [
        f"Distill analysis (window {window_days}d, {len(entries)} accepted uses):",
        "",
    ]
    sections: list[str] = []
    for c, n in hot_cases:
        lines.append(f"- case `{c}` succeeded {n}× in window")
        members = [
            e["object"] for e in entries
            if (v.get(e["object"]) and v.get(e["object"]).case_id == c)
        ]
        sections.append(
            f"## Case `{c}` — {n} lessons\n\n"
            + "\n".join(f"- {m}" for m in members)
            + "\n\nSuggested: distill these into one playbook lesson; mark members "
            "superseded after approval.\n"
        )
    for t, n in hot_tags:
        lines.append(f"- tag `{t}` appeared {n}× in window")
        sections.append(
            f"## Tag `{t}` — {n} occurrences\n\nSuggested: consolidate recurring "
            f"`{t}` lessons into one distilled lesson after approval.\n"
        )

    with v.locked():  # proposal + audit log as one atomic unit
        proposal_path = _next_proposal_path(v, "distill")
        atomic_write(
            proposal_path,
            "# Distill proposal — auto-generated\n\n"
            f"Window: {window_days} days · threshold: {min_repeat}\n\n"
            + "\n".join(sections),
        )
        v._append_log_locked("distill", f"cases:{len(hot_cases)},tags:{len(hot_tags)}")
    lines += ["", f"Proposal written: {v.relpath(proposal_path)} — human approval required."]
    return "\n".join(lines)


def memory_profile(vault: Vault | None = None) -> str:
    try:
        v = _open_vault(vault)
    except VaultNotInitialized as e:
        return str(e)
    text = Profile(v).read()
    if not text:
        return (
            "Profile is empty. The owner may maintain stable facts under "
            "Agent-Profile/Immutable/. Maintain global preferences through the "
            "memory_profile_* tools."
        )
    return text


def memory_suggest(title: str, change: str, vault: Vault | None = None) -> str:
    """Backward-compatible alias for a profile suggestion."""
    return memory_profile_suggest(title, change, "", vault)


def memory_profile_suggest(
    key: str, value: str, reason: str = "", vault: Vault | None = None
) -> str:
    try:
        v = _open_vault(vault)
    except VaultNotInitialized as e:
        return str(e)
    try:
        path = Profile(v).suggest(key, value, reason)
    except ValueError as e:
        return f"Refused: {e}."
    v.append_log("profile-suggest", v.relpath(path))
    _meta, _body = parse(path.read_text(encoding="utf-8-sig"))
    old_value = str(_meta.get("old_value", ""))
    return (
        f"Profile suggestion saved: {path.stem}\n"
        f"{key}: {old_value or '(empty)'} → {value}\n"
        "It is pending and does not affect the current profile."
    )


def memory_profile_set(
    key: str, value: str, reason: str = "", vault: Vault | None = None
) -> str:
    """Add an explicit global preference; existing preferences require review."""
    try:
        v = _open_vault(vault)
    except VaultNotInitialized as e:
        return str(e)
    try:
        old, new = Profile(v).set(key, value, reason)
    except ValueError as e:
        return f"Refused: {e}."
    if old == new:
        return f"Profile unchanged: {key} is already {new}"
    v.append_log("profile-set", key)
    return f"Profile updated: {key} · {old or '(empty)'} → {new}"


def memory_profile_apply(suggestion_id: str, vault: Vault | None = None) -> str:
    try:
        v = _open_vault(vault)
    except VaultNotInitialized as e:
        return str(e)
    try:
        key, old, new = Profile(v).apply(suggestion_id)
    except (ValueError, FileNotFoundError) as e:
        return f"Refused: {e}."
    v.append_log("profile-apply", suggestion_id)
    return f"Profile suggestion applied: {key} · {old or '(empty)'} → {new}"


def memory_profile_reject(
    suggestion_id: str, reason: str = "", vault: Vault | None = None
) -> str:
    try:
        v = _open_vault(vault)
    except VaultNotInitialized as e:
        return str(e)
    try:
        key = Profile(v).reject(suggestion_id, reason)
    except (ValueError, FileNotFoundError) as e:
        return f"Refused: {e}."
    v.append_log("profile-reject", suggestion_id)
    return f"Profile suggestion rejected: {key}"


def memory_profile_remove(
    key: str, reason: str = "", vault: Vault | None = None
) -> str:
    """Remove a global preference only after the owner confirmed its old value."""
    try:
        v = _open_vault(vault)
    except VaultNotInitialized as e:
        return str(e)
    try:
        old = Profile(v).remove(key, reason)
    except ValueError as e:
        return f"Refused: {e}."
    v.append_log("profile-remove", key)
    return f"Profile removed: {key} · {old} → (removed)"


def memory_profile_history(key: str = "", vault: Vault | None = None) -> str:
    try:
        v = _open_vault(vault)
    except VaultNotInitialized as e:
        return str(e)
    return Profile(v).history(key)
