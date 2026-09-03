from agentbrain import api
from tests.helpers import lesson_text


def test_query_empty_result_hint(vault):
    out = api.memory_query("zzzunmatchedqueryxyz", vault=vault)
    assert "No lessons matched" in out


def test_ingest_and_query_flow(vault):
    out = api.memory_ingest(
        case_id="case-001",
        lesson=lesson_text("部署前必须先跑数据库迁移脚本"),
        tags=["部署", "运维"],
        vault=vault,
    )
    assert "Saved case-001-lesson-01" in out

    out = api.memory_query("部署 迁移", vault=vault)
    assert "case-001-lesson-01" in out

    lesson = vault.get("case-001-lesson-01")
    assert lesson.use_count == 0
    assert lesson.verified is False

    out = api.memory_feedback(
        "case-001-lesson-01",
        "correct",
        "按经验在部署前执行了数据库迁移",
        "迁移完成且部署验收通过",
        vault=vault,
    )
    assert "Feedback accepted" in out
    lesson = vault.get("case-001-lesson-01")
    assert lesson.use_count == 1
    assert lesson.verified is True


def test_ingest_refuses_empty_lesson(vault):
    assert "Refused" in api.memory_ingest(case_id="c", lesson="  ", vault=vault)


def test_ingest_requires_complete_ordered_sections(vault):
    out = api.memory_ingest(case_id="c", lesson="单行经验", vault=vault)
    assert "exactly these non-empty sections in order" in out

    out = api.memory_ingest(
        case_id="c",
        lesson=(
            "## 经验教训\n结论\n\n## 适用场景\n\n## 规避方案\n做法"
        ),
        vault=vault,
    )
    assert "section '适用场景' must not be empty" in out
    assert vault.get("c-lesson-01") is None


def test_ingest_refuses_sensitive_values_without_blocking_security_rules(vault):
    out = api.memory_ingest(
        case_id="secret",
        lesson=lesson_text("连接密码：actual-password-123"),
        vault=vault,
    )
    assert "suspected sensitive value" in out
    assert vault.get("secret-lesson-01") is None

    out = api.memory_ingest(
        case_id="rule",
        lesson=lesson_text("不得保存密码、令牌、私钥或其他可直接使用的敏感值。"),
        vault=vault,
    )
    assert out.startswith("Saved rule-lesson-01")


def test_revise_enforces_write_checks_and_confidence_minimum(vault):
    api.memory_ingest(case_id="c", lesson=lesson_text("原经验"), vault=vault)

    out = api.memory_revise(
        "c-lesson-01", "缺少三段", "修改", "原因", vault=vault
    )
    assert "Refused" in out
    assert vault.get("c-lesson-01").revision == 1

    out = api.memory_revise(
        "c-lesson-01",
        lesson_text("新经验"),
        "修改",
        "token=actual-token-value",
        vault=vault,
    )
    assert "suspected sensitive value" in out
    assert vault.get("c-lesson-01").revision == 1

    out = api.memory_revise(
        "c-lesson-01",
        lesson_text("新经验"),
        "修改",
        "原因",
        confidence=0.0,
        vault=vault,
    )
    assert "conf 0.1" in out
    assert vault.get("c-lesson-01").confidence == 0.1


def test_ingest_normalizes_tags_and_case(vault):
    out = api.memory_ingest(case_id="My Case/1", lesson=lesson_text("内容"), tags="a, a,, b", vault=vault)
    assert "My-Case-1-lesson-01" in out
    lesson = vault.get("My-Case-1-lesson-01")
    assert lesson.tags == ["a", "b"]


def test_lint_detects_duplicates(vault):
    api.memory_ingest(case_id="c1", lesson=lesson_text("always pin dependencies in requirements.txt"), tags=["deps"], source_summary="pin dependencies", vault=vault)
    api.memory_ingest(case_id="c2", lesson=lesson_text("always pin your dependencies in the requirements file"), tags=["deps"], source_summary="pin dependencies exactly", vault=vault)
    out = api.memory_lint(vault=vault)
    assert "DUPLICATE" in out
    assert any(p.name.startswith("lint-") for p in vault.consolidations_dir.glob("*.md"))


def test_lint_clean_vault(vault):
    out = api.memory_lint(vault=vault)
    assert "clean" in out.lower()


def test_lint_scope_tag(vault):
    api.memory_ingest(case_id="c1", lesson=lesson_text("content about database indexes"), tags=["db"], confidence=0.3, vault=vault)
    api.memory_ingest(case_id="c2", lesson=lesson_text("content about css flexbox layout"), tags=["ui"], confidence=0.3, vault=vault)
    out = api.memory_lint(scope="tag:ui", vault=vault)
    assert "c2-lesson-01" in out
    assert "c1-lesson-01" not in out


def test_distill_no_pattern(vault):
    out = api.memory_distill(window_days=30, min_repeat=3, vault=vault)
    assert "Nothing to distill" in out


def test_distill_finds_recurring_tag(vault):
    for i in range(3):
        api.memory_ingest(case_id=f"c-{i}", lesson=lesson_text(f"lesson {i} about deployment"), tags=["部署"], vault=vault)
        api.memory_feedback(
            f"c-{i}-lesson-01",
            "correct",
            "按经验调整了部署动作",
            "部署验收通过",
            vault=vault,
        )
    out = api.memory_distill(window_days=30, min_repeat=3, vault=vault)
    assert "部署" in out
    assert any(p.name.startswith("distill-") for p in vault.consolidations_dir.glob("*.md"))


def test_not_initialized_returns_hint(tmp_path, monkeypatch):
    monkeypatch.setenv("AGENTBRAIN_VAULT", str(tmp_path / "nope"))
    out = api.memory_query("x")
    assert "agentbrain init" in out
