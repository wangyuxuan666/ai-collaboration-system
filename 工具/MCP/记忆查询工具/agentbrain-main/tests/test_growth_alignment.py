from agentbrain import api
from tests.helpers import lesson_text


def test_ingest_defaults_to_unverified(vault):
    api.memory_ingest(case_id="c", lesson=lesson_text("new lesson"), vault=vault)
    lesson = vault.get("c-lesson-01")
    assert lesson.confidence == 0.5
    assert lesson.verified is False
    assert lesson.last_verified_at == ""


def test_feedback_calibrates_only_after_actual_use(vault):
    api.memory_ingest(case_id="c", lesson=lesson_text("feedback target"), confidence=0.5, vault=vault)
    api.memory_query("feedback target", vault=vault)
    lesson = vault.get("c-lesson-01")
    assert lesson.use_count == 0

    api.memory_feedback(
        "c-lesson-01",
        "correct",
        "经验改变了执行动作",
        "改变后的动作通过验收",
        vault=vault,
    )
    lesson = vault.get("c-lesson-01")
    assert lesson.use_count == 1
    assert lesson.confidence == 0.6
    assert lesson.verified is True

    api.memory_feedback(
        "c-lesson-01",
        "wrong",
        "经验改变了执行动作",
        "改变后的动作被用户纠正",
        vault=vault,
    )
    lesson = vault.get("c-lesson-01")
    assert lesson.failure_count == 1
    assert lesson.confidence == 0.5
    assert lesson.verified is False


def test_feedback_requires_effect_and_evidence(vault):
    api.memory_ingest(case_id="f", lesson=lesson_text("feedback guard"), vault=vault)
    assert "Refused: effect is required" in api.memory_feedback(
        "f-lesson-01", "correct", "", "验收通过", vault=vault
    )
    assert "Refused: evidence is required" in api.memory_feedback(
        "f-lesson-01", "correct", "改变了行动", "", vault=vault
    )
    lesson = vault.get("f-lesson-01")
    assert lesson.use_count == 0
    assert lesson.failure_count == 0


def test_revision_history_accumulates(vault):
    api.memory_ingest(case_id="c", lesson=lesson_text("v1"), source_summary="stable", vault=vault)
    api.memory_revise("c-lesson-01", lesson_text("v2"), "first", "reason", vault=vault)
    api.memory_revise("c-lesson-01", lesson_text("v3"), "second", "reason", vault=vault)
    out = api.memory_history("c-lesson-01", vault=vault)
    assert "| v2 |" in out
    assert "| v3 |" in out
    assert vault.get("c-lesson-01").source_summary == "stable"


def test_bom_lesson_is_readable(vault):
    path = vault.learnings_dir / "bom-lesson-01.md"
    path.write_text(
        "---\ncase_id: bom\nsource_summary: BOM readable\ntags: [bom]\n"
        "created_at: '2026-01-01'\nconfidence: 0.5\n---\n\nbody\n",
        encoding="utf-8-sig",
    )
    assert vault.get("bom-lesson-01") is not None


def test_legacy_migration_preserves_query_count(vault):
    lesson = vault.new_lesson("legacy", "old", "body", [])
    lesson.use_count = 4
    vault.save(lesson)
    path = lesson.path
    text = path.read_text(encoding="utf-8").replace("retrieval_count: 0\n", "")
    path.write_text(text, encoding="utf-8-sig")

    assert vault.migrate_legacy_lessons() == 1
    migrated = vault.get("legacy-lesson-01")
    assert migrated.retrieval_count == 4
    assert migrated.use_count == 0
    assert path.read_bytes()[:3] != b"\xef\xbb\xbf"
