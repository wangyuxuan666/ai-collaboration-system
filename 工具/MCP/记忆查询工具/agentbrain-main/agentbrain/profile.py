from __future__ import annotations

import datetime as dt
import re
from pathlib import Path

from .frontmatter import dump, parse
from .locking import atomic_write
from .vault import Vault

_UNSAFE = re.compile(r"[^A-Za-z0-9\u4e00-\u9fff-]+")


def _oneline(value: str) -> str:
    return " ".join((value or "").strip().split())


def _table(value: str) -> str:
    return _oneline(value).replace("|", "/")


class Profile:
    """Read the profile and manage reviewed global preferences."""

    def __init__(self, vault: Vault):
        self.vault = vault
        self.root = vault.root / "Agent-Profile"
        self.immutable_dir = self.root / "Immutable"
        self.hints_dir = self.root / "Mutable-Hints"
        self.suggestions_dir = self.root / "_suggestions"
        self.preferences_md = self.hints_dir / "preferences.md"
        self.history_md = self.root / "_history" / "log.md"

    def _collect(self, directory: Path) -> list[tuple[str, str]]:
        out: list[tuple[str, str]] = []
        if not directory.is_dir():
            return out
        for path in sorted(directory.glob("*.md")):
            if path.name.lower() == "readme.md":
                continue
            try:
                text = path.read_text(encoding="utf-8-sig").strip()
            except OSError:
                continue
            _meta, body = parse(text)
            if body.strip():
                out.append((path.stem, body.strip()))
        return out

    def read(self) -> str:
        sections: list[str] = []
        for label, directory in (
            ("immutable", self.immutable_dir),
            ("hints", self.hints_dir),
        ):
            for stem, text in self._collect(directory):
                sections.append(f"## [{label}] {stem}\n\n{text}")
        return "\n\n".join(sections)

    def _load_preferences(self) -> dict[str, str]:
        if not self.preferences_md.is_file():
            return {}
        try:
            text = self.preferences_md.read_text(encoding="utf-8-sig")
        except OSError:
            return {}
        meta, _body = parse(text)
        raw = meta.get("preferences", {})
        if not isinstance(raw, dict):
            return {}
        return {
            _oneline(str(key)): _oneline(str(value))
            for key, value in raw.items()
            if _oneline(str(key)) and _oneline(str(value))
        }

    def _write_preferences_locked(self, preferences: dict[str, str]) -> None:
        self.hints_dir.mkdir(parents=True, exist_ok=True)
        body = "# 全局偏好"
        if preferences:
            body += "\n\n" + "\n".join(
                f"- {key}：{value}" for key, value in preferences.items()
            )
        atomic_write(self.preferences_md, dump({"preferences": preferences}, body))

    def _history_locked(
        self, action: str, key: str, old_value: str, new_value: str, reason: str
    ) -> None:
        self.history_md.parent.mkdir(parents=True, exist_ok=True)
        if self.history_md.is_file():
            text = self.history_md.read_text(encoding="utf-8-sig").rstrip()
        else:
            text = (
                "# Profile History\n\n"
                "| date | action | key | old | new | reason |\n"
                "|---|---|---|---|---|---|"
            )
        row = (
            f"| {dt.date.today().isoformat()} | {_table(action)} | {_table(key)} | "
            f"{_table(old_value)} | {_table(new_value)} | {_table(reason)} |"
        )
        atomic_write(self.history_md, f"{text}\n{row}\n")

    def set(self, key: str, value: str, reason: str = "") -> tuple[str, str]:
        key, value = _oneline(key), _oneline(value)
        if not key or not value:
            raise ValueError("key and value are required")
        with self.vault.locked():
            preferences = self._load_preferences()
            old_value = preferences.get(key, "")
            if old_value:
                if old_value == value:
                    return old_value, value
                raise ValueError(
                    "preference already exists; create a suggestion and apply it "
                    "only after the owner confirms the old and new values"
                )
            preferences[key] = value
            self._write_preferences_locked(preferences)
            self._history_locked("set", key, old_value, value, reason)
        return old_value, value

    def suggest(self, key: str, value: str, reason: str = "") -> Path:
        key, value = _oneline(key), _oneline(value)
        if not key or not value:
            raise ValueError("key and value are required")
        slug = _UNSAFE.sub("-", key).strip("-")[:40] or "suggestion"
        stamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
        with self.vault.locked():
            old_value = self._load_preferences().get(key, "")
            self.suggestions_dir.mkdir(parents=True, exist_ok=True)
            path = self.suggestions_dir / f"{stamp}-{slug}.md"
            n = 2
            while path.exists():
                path = self.suggestions_dir / f"{stamp}-{slug}-{n}.md"
                n += 1
            body = (
                f"# Profile 建议\n\n- 字段：{key}"
                f"\n- 原值：{old_value or '（不存在）'}\n- 建议值：{value}"
            )
            if reason:
                body += f"\n- 原因：{_oneline(reason)}"
            atomic_write(
                path,
                dump(
                    {
                        "key": key,
                        "old_value": old_value,
                        "value": value,
                        "reason": _oneline(reason),
                        "created_at": dt.date.today().isoformat(),
                        "status": "pending",
                    },
                    body,
                ),
            )
        return path

    def _suggestion(self, suggestion_id: str) -> tuple[Path, dict, str]:
        sid = Path((suggestion_id or "").strip()).stem
        if not sid or sid in (".", ".."):
            raise ValueError("suggestion_id is required")
        path = self.suggestions_dir / f"{sid}.md"
        if not path.is_file():
            raise FileNotFoundError(sid)
        text = path.read_text(encoding="utf-8-sig")
        meta, body = parse(text)
        return path, meta, body

    def apply(self, suggestion_id: str) -> tuple[str, str, str]:
        with self.vault.locked():
            path, meta, body = self._suggestion(suggestion_id)
            if meta.get("status") != "pending":
                raise ValueError(f"suggestion is {meta.get('status', 'invalid')}")
            key, value = _oneline(str(meta.get("key", ""))), _oneline(
                str(meta.get("value", ""))
            )
            if not key or not value:
                raise ValueError("suggestion has no key/value")
            preferences = self._load_preferences()
            old_value = preferences.get(key, "")
            if "old_value" in meta and _oneline(str(meta["old_value"])) != old_value:
                raise ValueError(
                    "profile changed after this suggestion was created; create a "
                    "new suggestion and confirm the latest old and new values"
                )
            preferences[key] = value
            self._write_preferences_locked(preferences)
            meta["status"] = "applied"
            meta["resolved_at"] = dt.date.today().isoformat()
            atomic_write(path, dump(meta, body))
            self._history_locked(
                "apply", key, old_value, value, str(meta.get("reason", ""))
            )
        return key, old_value, value

    def remove(self, key: str, reason: str = "") -> str:
        key = _oneline(key)
        if not key:
            raise ValueError("key is required")
        with self.vault.locked():
            preferences = self._load_preferences()
            old_value = preferences.get(key, "")
            if not old_value:
                raise ValueError("preference does not exist")
            del preferences[key]
            self._write_preferences_locked(preferences)
            self._history_locked("remove", key, old_value, "", reason)
        return old_value

    def reject(self, suggestion_id: str, reason: str = "") -> str:
        with self.vault.locked():
            path, meta, body = self._suggestion(suggestion_id)
            if meta.get("status") != "pending":
                raise ValueError(f"suggestion is {meta.get('status', 'invalid')}")
            meta["status"] = "rejected"
            meta["resolved_at"] = dt.date.today().isoformat()
            meta["rejection_reason"] = _oneline(reason)
            atomic_write(path, dump(meta, body))
            self._history_locked(
                "reject",
                str(meta.get("key", "")),
                str(meta.get("value", "")),
                "",
                reason,
            )
        return str(meta.get("key", ""))

    def history(self, key: str = "") -> str:
        if not self.history_md.is_file():
            return "No profile history."
        text = self.history_md.read_text(encoding="utf-8-sig")
        key = _oneline(key)
        if not key:
            return text
        rows = [line for line in text.splitlines() if line.startswith("|")]
        matched = [line for line in rows[2:] if len(line.split("|")) > 3 and line.split("|")[3].strip() == key]
        if not matched:
            return f"No profile history for: {key}"
        return "| date | action | key | old | new | reason |\n|---|---|---|---|---|---|\n" + "\n".join(matched)
