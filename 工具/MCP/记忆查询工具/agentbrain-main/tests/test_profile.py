import agentbrain.api as api
import pytest
from agentbrain.profile import Profile
from agentbrain.vault import Vault


def test_read_merges_layers_and_skips_readme(vault: Vault):
    (vault.root / "Agent-Profile" / "Mutable-Hints" / "hints.md").write_text(
        "# Hints\n\n- prefers bullet lists\n", encoding="utf-8"
    )
    text = Profile(vault).read()
    assert "[immutable] profile" in text
    assert "[hints] hints" in text
    assert "prefers bullet lists" in text
    assert "README" not in text


def test_read_empty_when_no_profile_files(vault: Vault):
    (vault.root / "Agent-Profile" / "Immutable" / "profile.md").unlink()
    assert Profile(vault).read() == ""


def test_suggest_writes_pending_file(vault: Vault):
    path = Profile(vault).suggest("Reply in English", "User switched to English; default to English replies.")
    assert path.parent == vault.root / "Agent-Profile" / "_suggestions"
    text = path.read_text(encoding="utf-8")
    assert "key: Reply in English" in text
    assert "status: pending" in text
    assert "English replies" in text


def test_set_updates_profile_and_history(vault: Vault):
    old, new = Profile(vault).set("回复语言", "中文", "用户明确要求")
    assert old == ""
    assert new == "中文"
    assert "回复语言：中文" in Profile(vault).read()
    history = Profile(vault).history("回复语言")
    assert "| set | 回复语言 |  | 中文 | 用户明确要求 |" in history


def test_set_refuses_to_overwrite_existing_preference(vault: Vault):
    profile = Profile(vault)
    profile.set("回复语言", "中文", "新增")
    with pytest.raises(ValueError, match="already exists"):
        profile.set("回复语言", "英文", "未经确认的修改")
    assert "回复语言：中文" in profile.read()


def test_apply_suggestion_updates_profile(vault: Vault):
    profile = Profile(vault)
    suggestion = profile.suggest("默认回答", "简短直接", "多次行为推测")
    assert "默认回答：简短直接" not in profile.read()
    key, old, new = profile.apply(suggestion.stem)
    assert (key, old, new) == ("默认回答", "", "简短直接")
    assert "默认回答：简短直接" in profile.read()
    assert "status: applied" in suggestion.read_text(encoding="utf-8")


def test_apply_refuses_when_confirmed_old_value_is_stale(vault: Vault):
    profile = Profile(vault)
    profile.set("默认回答", "简短", "新增")
    stale = profile.suggest("默认回答", "详细", "第一个建议")
    accepted = profile.suggest("默认回答", "适中", "用户后来确认的建议")
    profile.apply(accepted.stem)
    with pytest.raises(ValueError, match="changed after"):
        profile.apply(stale.stem)
    assert "默认回答：适中" in profile.read()


def test_remove_deletes_active_value_and_keeps_history(vault: Vault):
    profile = Profile(vault)
    profile.set("回答长度", "三句话内", "新增")
    assert profile.remove("回答长度", "用户确认删除") == "三句话内"
    assert "回答长度：三句话内" not in profile.read()
    assert "| remove | 回答长度 | 三句话内 |  | 用户确认删除 |" in profile.history(
        "回答长度"
    )


def test_reject_suggestion_does_not_update_profile(vault: Vault):
    profile = Profile(vault)
    suggestion = profile.suggest("展开方式", "总是详细", "AI 推测")
    assert profile.reject(suggestion.stem, "用户否定") == "展开方式"
    assert "展开方式：总是详细" not in profile.read()
    assert "status: rejected" in suggestion.read_text(encoding="utf-8")


def test_api_memory_profile(vault: Vault):
    out = api.memory_profile(vault=vault)
    assert "[immutable] profile" in out


def test_api_memory_suggest_logs(vault: Vault):
    out = api.memory_suggest(title="更简洁", change="回复控制在三句话以内", vault=vault)
    assert "Profile suggestion saved" in out
    assert "pending" in out
    assert "profile-suggest | Agent-Profile/_suggestions/" in vault.log_md.read_text(encoding="utf-8")


def test_api_memory_suggest_refuses_empty(vault: Vault):
    assert "Refused" in api.memory_suggest(title="", change="x", vault=vault)
    assert "Refused" in api.memory_suggest(title="t", change=" ", vault=vault)


def test_api_set_requires_review_for_existing_value(vault: Vault):
    assert "Profile updated" in api.memory_profile_set(
        "回答风格", "简短", "用户明确新增", vault
    )
    out = api.memory_profile_set("回答风格", "详细", "用户提出修改", vault)
    assert "Refused" in out
    assert "create a suggestion" in out


def test_api_remove(vault: Vault):
    api.memory_profile_set("回答长度", "三句话内", "新增", vault)
    out = api.memory_profile_remove("回答长度", "用户确认删除", vault)
    assert "Profile removed" in out
    assert "profile-remove | 回答长度" in vault.log_md.read_text(encoding="utf-8")


def test_api_memory_profile_empty_hint(vault: Vault):
    (vault.root / "Agent-Profile" / "Immutable" / "profile.md").unlink()
    assert "Profile is empty" in api.memory_profile(vault=vault)
