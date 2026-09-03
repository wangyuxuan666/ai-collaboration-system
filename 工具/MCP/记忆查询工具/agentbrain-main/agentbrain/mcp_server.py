from __future__ import annotations

try:  # mcp >= 2.0
    from mcp.server.mcpserver import MCPServer as _Server
except ImportError:  # mcp 1.x
    from mcp.server.fastmcp import FastMCP as _Server

from . import api
from .config import Config
from .profile import Profile
from .vault import Vault, VaultNotInitialized

mcp = _Server("agentbrain")


def memory_query(query: str, top_k: int = 5, mode: str = "index") -> str:
    return api.memory_query(query=query, top_k=top_k, mode=mode)


def memory_ingest(
    case_id: str,
    lesson: str,
    tags: list[str] | None = None,
    confidence: float = 0.5,
    source_summary: str | None = None,
) -> str:
    return api.memory_ingest(
        case_id=case_id,
        lesson=lesson,
        tags=tags,
        confidence=confidence,
        source_summary=source_summary,
    )


def memory_lint(scope: str = "all") -> str:
    return api.memory_lint(scope=scope)


def memory_consolidation_apply(proposal: str) -> str:
    return api.memory_consolidation_apply(proposal=proposal)


def memory_distill(window_days: int = 30, min_repeat: int = 3) -> str:
    return api.memory_distill(window_days=window_days, min_repeat=min_repeat)


def memory_profile() -> str:
    return api.memory_profile()


def memory_profile_suggest(key: str, value: str, reason: str = "") -> str:
    return api.memory_profile_suggest(key=key, value=value, reason=reason)


def memory_profile_set(key: str, value: str, reason: str = "") -> str:
    return api.memory_profile_set(key=key, value=value, reason=reason)


def memory_profile_apply(suggestion_id: str) -> str:
    return api.memory_profile_apply(suggestion_id=suggestion_id)


def memory_profile_reject(suggestion_id: str, reason: str = "") -> str:
    return api.memory_profile_reject(suggestion_id=suggestion_id, reason=reason)


def memory_profile_remove(key: str, reason: str = "") -> str:
    return api.memory_profile_remove(key=key, reason=reason)


def memory_profile_history(key: str = "") -> str:
    return api.memory_profile_history(key=key)


def memory_revise(
    lesson_id: str,
    lesson: str,
    change: str,
    reason: str = "",
    confidence: float | None = None,
    source_summary: str | None = None,
    tags: list[str] | None = None,
) -> str:
    return api.memory_revise(
        lesson_id=lesson_id,
        lesson=lesson,
        change=change,
        reason=reason,
        confidence=confidence,
        source_summary=source_summary,
        tags=tags,
    )


def memory_history(lesson_id: str) -> str:
    return api.memory_history(lesson_id=lesson_id)


def memory_feedback(
    lesson_id: str, result: str, effect: str, evidence: str
) -> str:
    return api.memory_feedback(
        lesson_id=lesson_id,
        result=result,
        effect=effect,
        evidence=evidence,
    )


mcp.add_tool(memory_query)
mcp.add_tool(memory_ingest)
mcp.add_tool(memory_revise)
mcp.add_tool(memory_history)
mcp.add_tool(memory_feedback)
mcp.add_tool(memory_lint)
mcp.add_tool(memory_consolidation_apply)
mcp.add_tool(memory_distill)
mcp.add_tool(memory_profile)
mcp.add_tool(memory_profile_suggest)
mcp.add_tool(memory_profile_set)
mcp.add_tool(memory_profile_apply)
mcp.add_tool(memory_profile_reject)
mcp.add_tool(memory_profile_remove)
mcp.add_tool(memory_profile_history)


def _open() -> Vault | None:
    try:
        return Vault.open(Config.load())
    except VaultNotInitialized:
        return None


@mcp.resource("agentbrain://rules", description="Vault rules every agent must follow (AGENTS.md)")
def _rules_resource() -> str:
    v = _open()
    if v is None:
        return "Vault not initialized. Run: agentbrain init"
    p = v.root / "AGENTS.md"
    return p.read_text(encoding="utf-8") if p.is_file() else "AGENTS.md not found."


@mcp.resource("agentbrain://index", description="Lesson index — retrieval layer 1 (Case-Learnings/Index.md)")
def _index_resource() -> str:
    v = _open()
    if v is None:
        return "Vault not initialized. Run: agentbrain init"
    if v.index_md.is_file():
        return v.index_md.read_text(encoding="utf-8")
    return "Index.md not found yet — ingest a lesson first."


@mcp.resource("agentbrain://profile", description="Owner profile: stable facts + active global preferences (read-only)")
def _profile_resource() -> str:
    v = _open()
    if v is None:
        return "Vault not initialized. Run: agentbrain init"
    return Profile(v).read() or "Profile is empty."


def main() -> None:
    mcp.run()
