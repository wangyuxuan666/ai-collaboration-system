import asyncio

from tests.helpers import lesson_text


def test_mcp_tools_registered():
    from agentbrain import mcp_server

    tools = asyncio.run(mcp_server.mcp.list_tools())
    names = {t.name for t in tools}
    assert {
        "memory_query",
        "memory_ingest",
        "memory_revise",
        "memory_history",
        "memory_feedback",
        "memory_lint",
        "memory_consolidation_apply",
        "memory_distill",
        "memory_profile",
        "memory_suggest",
        "memory_profile_suggest",
        "memory_profile_set",
        "memory_profile_apply",
        "memory_profile_reject",
        "memory_profile_remove",
        "memory_profile_history",
    } <= names


def _result_text(result) -> str:
    content = getattr(result, "content", None)
    if content is None:
        content = result[0] if isinstance(result, tuple) else result
    return content[0].text


def test_mcp_tool_call_end_to_end(tmp_path, monkeypatch):
    from agentbrain import mcp_server, scaffold

    root = tmp_path / "vault"
    scaffold.init(root)
    monkeypatch.setenv("AGENTBRAIN_VAULT", str(root))

    async def invalid_call():
        return await mcp_server.mcp.call_tool(
            "memory_ingest",
            {"case_id": "c-mcp", "lesson": "缺少三段式"},
        )

    assert "Refused" in _result_text(asyncio.run(invalid_call()))

    result = mcp_server.memory_ingest(
        case_id="c-mcp",
        lesson=lesson_text("MCP 工具调用要处理超时"),
        tags=["mcp"],
        confidence=0.0,
    )
    assert "Saved c-mcp-lesson-01" in result
    assert "confidence 0.1" in result

    async def call():
        return await mcp_server.mcp.call_tool("memory_query", {"query": "MCP 超时"})

    assert "c-mcp-lesson-01" in _result_text(asyncio.run(call()))


def test_mcp_consolidation_apply(tmp_path, monkeypatch):
    from agentbrain import api, mcp_server, scaffold
    from agentbrain.vault import Vault

    root = tmp_path / "vault"
    scaffold.init(root)
    monkeypatch.setenv("AGENTBRAIN_VAULT", str(root))
    vault = Vault.open(root=root)
    for case_id in ("dup-a", "dup-b"):
        api.memory_ingest(
            case_id=case_id,
            lesson=lesson_text("修改画像前必须核对旧值"),
            tags=["画像", "确认"],
            source_summary="修改画像前核对旧值",
            vault=vault,
        )
    lint = api.memory_lint(vault=vault)
    proposal = lint.split("Proposal written: ", 1)[1].splitlines()[0]

    out = mcp_server.memory_consolidation_apply(proposal)
    assert "Applied 1 directive(s)" in out
    active = [lesson for lesson in vault.lessons() if lesson.case_id.startswith("dup-")]
    assert len(active) == 1
    assert len(list(vault.consolidations_dir.glob("*.applied.md"))) == 1
    assert "Refused" in mcp_server.memory_consolidation_apply(proposal)


def test_mcp_profile_and_suggest(tmp_path, monkeypatch):
    from agentbrain import mcp_server, scaffold

    root = tmp_path / "vault"
    scaffold.init(root)
    monkeypatch.setenv("AGENTBRAIN_VAULT", str(root))

    assert "[immutable] profile" in mcp_server.memory_profile()

    out = mcp_server.memory_suggest(title="用中文回复", change="Owner prefers Chinese replies.")
    assert "Profile suggestion saved" in out

    suggestion_id = out.splitlines()[0].split(": ", 1)[1]
    assert "Profile suggestion applied" in mcp_server.memory_profile_apply(suggestion_id)
    assert "用中文回复：Owner prefers Chinese replies." in mcp_server.memory_profile()
    assert "| apply | 用中文回复 |" in mcp_server.memory_profile_history("用中文回复")

    rejected = mcp_server.memory_profile_suggest("回答长度", "三句话内", "AI 推测")
    rejected_id = rejected.splitlines()[0].split(": ", 1)[1]
    assert "Profile suggestion rejected" in mcp_server.memory_profile_reject(
        rejected_id, "用户否定"
    )
    assert "回答长度：三句话内" not in mcp_server.memory_profile()

    assert "Profile updated" in mcp_server.memory_profile_set(
        "回复语言", "中文", "用户明确要求"
    )
    assert "回复语言：中文" in mcp_server.memory_profile()
    assert "Refused" in mcp_server.memory_profile_set(
        "回复语言", "英文", "尚未二次确认"
    )
    assert "Profile removed" in mcp_server.memory_profile_remove(
        "回复语言", "用户确认删除"
    )
    assert "回复语言：中文" not in mcp_server.memory_profile()


def test_mcp_resources(tmp_path, monkeypatch):
    from agentbrain import mcp_server, scaffold

    root = tmp_path / "vault"
    scaffold.init(root)
    monkeypatch.setenv("AGENTBRAIN_VAULT", str(root))

    async def run():
        resources = await mcp_server.mcp.list_resources()
        uris = {str(r.uri) for r in resources}
        rules = await mcp_server.mcp.read_resource("agentbrain://rules")
        index = await mcp_server.mcp.read_resource("agentbrain://index")
        profile = await mcp_server.mcp.read_resource("agentbrain://profile")
        return uris, rules, index, profile

    uris, rules, index, profile = asyncio.run(run())
    assert uris == {
        "agentbrain://rules",
        "agentbrain://index",
        "agentbrain://profile",
    }
    assert "Profile lifecycle" in rules[0].content
    assert "Case-Learnings Index" in index[0].content
    assert "[immutable] profile" in profile[0].content


def test_mcp_resources_without_vault(tmp_path, monkeypatch):
    from agentbrain import mcp_server

    monkeypatch.setenv("AGENTBRAIN_VAULT", str(tmp_path / "missing"))

    async def run():
        return await mcp_server.mcp.read_resource("agentbrain://index")

    assert "not initialized" in asyncio.run(run())[0].content
