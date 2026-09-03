from __future__ import annotations

import argparse
import sys
from pathlib import Path

from . import __version__, api, scaffold
from .config import Config
from .vault import Vault, VaultNotInitialized


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="agentbrain",
        description="Local-first long-term memory for AI agents (Markdown vault + MCP server).",
    )
    parser.add_argument("--vault", help="Vault directory (default: $AGENTBRAIN_VAULT or ~/agentbrain)")
    parser.add_argument("--version", action="version", version=f"%(prog)s {__version__}")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("init", help="Create/scaffold a memory vault")
    p.add_argument("path", nargs="?", help="Vault directory (default: --vault/$AGENTBRAIN_VAULT/~/agentbrain)")
    p.add_argument("--force", action="store_true", help="Overwrite template files that already exist")

    p = sub.add_parser("query", help="Search lessons")
    p.add_argument("query")
    p.add_argument("-k", "--top-k", type=int, default=5)
    p.add_argument("--full", action="store_true", help="Print full lesson text for top hits")

    p = sub.add_parser("ingest", help="Save a new lesson")
    p.add_argument("--case", default="misc", help="Case id (default: misc)")
    p.add_argument("--lesson", required=True, help="Lesson text (facts + scenario + fix)")
    p.add_argument("--tags", default="", help="Comma-separated tags")
    p.add_argument("--confidence", type=float, default=0.5)
    p.add_argument("--summary", default=None, help="One-line summary (<= 60 chars); auto-derived if omitted")

    p = sub.add_parser("lint", help="Vault health check + consolidation proposal")
    p.add_argument("--scope", default="all", help='"all" or "tag:xxx"')

    p = sub.add_parser("distill", help="Recurring-pattern analysis + promotion proposal")
    p.add_argument("--window-days", type=int, default=30)
    p.add_argument("--min-repeat", type=int, default=3)

    sub.add_parser("index", help="Rebuild Case-Learnings/Index.md")
    sub.add_parser("path", help="Print resolved vault path")

    p = sub.add_parser("profile", help="Print stable owner facts and active global preferences")
    p = sub.add_parser("suggest", help="Propose a profile change (goes to Agent-Profile/_suggestions/)")
    p.add_argument("--title", required=True, help="Short title for the suggestion")
    p.add_argument("--change", required=True, help="What should change and why")

    p = sub.add_parser("profile-suggest", help="Propose a new or changed global preference")
    p.add_argument("--key", required=True)
    p.add_argument("--value", required=True)
    p.add_argument("--reason", default="")

    p = sub.add_parser("profile-set", help="Add an explicit owner preference")
    p.add_argument("--key", required=True)
    p.add_argument("--value", required=True)
    p.add_argument("--reason", default="")

    p = sub.add_parser("profile-apply", help="Apply a confirmed profile suggestion")
    p.add_argument("suggestion_id")

    p = sub.add_parser("profile-reject", help="Reject a profile suggestion")
    p.add_argument("suggestion_id")
    p.add_argument("--reason", default="")

    p = sub.add_parser("profile-remove", help="Remove a confirmed profile preference")
    p.add_argument("--key", required=True)
    p.add_argument("--reason", default="")

    p = sub.add_parser("profile-history", help="Show profile change history")
    p.add_argument("--key", default="")

    p = sub.add_parser("history", help="Show one lesson's revision history")
    p.add_argument("lesson_id")

    p = sub.add_parser("revise", help="Revise one lesson while preserving its id and history")
    p.add_argument("lesson_id")
    p.add_argument("--lesson", required=True)
    p.add_argument("--change", required=True)
    p.add_argument("--reason", default="")
    p.add_argument("--confidence", type=float, default=None)
    p.add_argument("--summary", default=None)
    p.add_argument("--tags", default=None, help="Comma-separated replacement tags")

    p = sub.add_parser("feedback", help="Record the outcome of an applied lesson")
    p.add_argument("lesson_id")
    p.add_argument("--result", choices=("correct", "wrong"), required=True)
    p.add_argument("--effect", required=True, help="What action changed because of the lesson")
    p.add_argument("--evidence", required=True, help="Evidence that the changed action worked or failed")

    sub.add_parser("migrate", help="Migrate legacy query counters to the feedback schema")

    p = sub.add_parser("apply", help="Execute an approved consolidation proposal")
    p.add_argument("proposal", help="Proposal file: bare name in _consolidations/, vault-relative or absolute path")

    sub.add_parser("serve", help="Start the MCP server on stdio")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)

    if args.cmd == "init":
        root = args.path or args.vault or Config.load().vault_dir
        print(scaffold.init(Path(root), force=args.force))
        return 0
    if args.cmd == "path":
        print(Config.load(args.vault).vault_dir)
        return 0
    if args.cmd == "serve":
        from . import mcp_server

        mcp_server.main()
        return 0

    try:
        vault = Vault.open(Config.load(args.vault))
    except VaultNotInitialized as e:
        print(str(e), file=sys.stderr)
        return 2

    if args.cmd == "query":
        print(api.memory_query(query=args.query, top_k=args.top_k, mode="full" if args.full else "index", vault=vault))
    elif args.cmd == "ingest":
        tags = [t.strip() for t in args.tags.split(",") if t.strip()]
        print(api.memory_ingest(case_id=args.case, lesson=args.lesson, tags=tags, confidence=args.confidence, source_summary=args.summary, vault=vault))
    elif args.cmd == "lint":
        print(api.memory_lint(scope=args.scope, vault=vault))
    elif args.cmd == "distill":
        print(api.memory_distill(window_days=args.window_days, min_repeat=args.min_repeat, vault=vault))
    elif args.cmd == "index":
        vault.rebuild_index()
        print(f"Index rebuilt: {vault.relpath(vault.index_md)}")
    elif args.cmd == "profile":
        print(api.memory_profile(vault=vault))
    elif args.cmd == "suggest":
        print(api.memory_suggest(title=args.title, change=args.change, vault=vault))
    elif args.cmd == "profile-suggest":
        print(api.memory_profile_suggest(
            key=args.key, value=args.value, reason=args.reason, vault=vault
        ))
    elif args.cmd == "profile-set":
        print(api.memory_profile_set(
            key=args.key, value=args.value, reason=args.reason, vault=vault
        ))
    elif args.cmd == "profile-apply":
        print(api.memory_profile_apply(args.suggestion_id, vault=vault))
    elif args.cmd == "profile-reject":
        print(api.memory_profile_reject(
            args.suggestion_id, reason=args.reason, vault=vault
        ))
    elif args.cmd == "profile-remove":
        print(api.memory_profile_remove(
            key=args.key, reason=args.reason, vault=vault
        ))
    elif args.cmd == "profile-history":
        print(api.memory_profile_history(key=args.key, vault=vault))
    elif args.cmd == "history":
        print(api.memory_history(lesson_id=args.lesson_id, vault=vault))
    elif args.cmd == "revise":
        tags = None if args.tags is None else [t.strip() for t in args.tags.split(",") if t.strip()]
        print(api.memory_revise(
            lesson_id=args.lesson_id,
            lesson=args.lesson,
            change=args.change,
            reason=args.reason,
            confidence=args.confidence,
            source_summary=args.summary,
            tags=tags,
            vault=vault,
        ))
    elif args.cmd == "feedback":
        print(api.memory_feedback(
            lesson_id=args.lesson_id,
            result=args.result,
            effect=args.effect,
            evidence=args.evidence,
            vault=vault,
        ))
    elif args.cmd == "migrate":
        count = vault.migrate_legacy_lessons()
        print(f"Migrated {count} legacy lesson(s).")
    elif args.cmd == "apply":
        from .apply import ProposalError, apply_proposal

        try:
            print(apply_proposal(vault, args.proposal))
        except ProposalError as e:
            print(str(e), file=sys.stderr)
            return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
