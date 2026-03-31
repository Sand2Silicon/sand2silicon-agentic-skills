#!/usr/bin/env python3
"""Sync OpenSpec tasks.md state from Beads issue statuses.

Run automatically via Claude Code Stop hook, or manually:
  python3 ${CLAUDE_PLUGIN_ROOT}/scripts/sync-openspec-tasks.py

For each Beads issue whose description contains a scoped task ref like
`change:signal-generation/tasks.md: X.Y`:
  - in_progress bead  →  marks task [~]  (claimed/underway)
  - closed bead       →  marks task [x]  (complete; overrides [~])

Unscoped refs (`tasks.md: X.Y`) are matched only when a single active
(non-archived) change exists, to prevent cross-change contamination.

When all tasks in a change are complete with high confidence, auto-archives the
change. When confidence is uncertain, prompts the user instead.

Confidence is HIGH (auto-archive) when:
- Every tasks.md checkbox is [x]
- Every [x] task has a corresponding closed Beads issue (1:1 coverage)
- No open Beads issues reference this change's tasks

Confidence is LOW (prompt user) when:
- Some [x] tasks have no matching closed bead (could be manually marked)
- Open Beads issues still reference tasks in this change
"""

import json
import re
import subprocess
import sys
from pathlib import Path


WORKSPACE = Path.cwd()
OPENSPEC_CHANGES = WORKSPACE / "openspec" / "changes"

# Scoped format: change:<name>/tasks.md: X.Y (preferred)
SCOPED_REF_PATTERN = re.compile(r"change:([\w-]+)/tasks\.md:?\s*([\d]+\.[\d]+)(?!\d)")
# Legacy unscoped format: tasks.md: X.Y (ambiguous across changes)
UNSCOPED_REF_PATTERN = re.compile(r"tasks\.md:?\s*([\d]+\.[\d]+)(?!\d)")
# Matches [ ] and [~] tasks — both transition to [x] on bead closure
OPEN_TASK_PATTERN = re.compile(r"^(\s*- \[[ ~]\] )([\d]+\.[\d]+)(?!\d)(\b.*)", re.MULTILINE)
# Matches only [ ] tasks — transition to [~] on bead claim (not already in-progress or done)
UNOPENED_TASK_PATTERN = re.compile(r"^(\s*- \[ \] )([\d]+\.[\d]+)(?!\d)(\b.*)", re.MULTILINE)
DONE_TASK_PATTERN = re.compile(r"- \[x\] ([\d]+\.[\d]+)(?!\d)", re.MULTILINE)


def get_issues_by_status(status: str) -> list[dict]:
    result = subprocess.run(
        ["bd", "list", f"--status={status}", "--json"],
        capture_output=True, text=True, cwd=WORKSPACE
    )
    if result.returncode != 0:
        return []
    try:
        return json.loads(result.stdout)
    except (json.JSONDecodeError, ValueError):
        return []


def collect_task_refs_by_change(issues: list[dict]) -> dict[str, set[str]]:
    """Return task refs grouped by change name.

    Scoped refs (change:<name>/tasks.md: X.Y) are placed under their change.
    Unscoped refs (tasks.md: X.Y) are placed under the key '__unscoped__'.
    """
    refs: dict[str, set[str]] = {}
    for issue in issues:
        desc = issue.get("description", "")
        for m in SCOPED_REF_PATTERN.finditer(desc):
            change_name = m.group(1)
            task_ref = m.group(2)
            refs.setdefault(change_name, set()).add(task_ref)
        # Only collect unscoped refs if no scoped ref was found in this issue
        # (avoids double-counting if someone uses both formats)
        if not SCOPED_REF_PATTERN.search(desc):
            for m in UNSCOPED_REF_PATTERN.finditer(desc):
                refs.setdefault("__unscoped__", set()).add(m.group(1))
    return refs


def resolve_refs_for_change(
    change: str,
    refs_by_change: dict[str, set[str]],
    active_changes: list[str],
) -> set[str]:
    """Get the task refs applicable to a specific change.

    Scoped refs matching this change are always included.
    Unscoped refs are included ONLY if this is the sole active change
    (to prevent cross-change contamination).
    """
    result = set(refs_by_change.get(change, set()))
    unscoped = refs_by_change.get("__unscoped__", set())
    if unscoped and len(active_changes) == 1 and active_changes[0] == change:
        result |= unscoped
    return result


def find_tasks_files() -> list[Path]:
    if not OPENSPEC_CHANGES.exists():
        return []
    return sorted(OPENSPEC_CHANGES.glob("*/tasks.md"))


def mark_tasks_complete(tasks_file: Path, refs: set[str]) -> tuple[str, list[str]]:
    """Mark matching open tasks as [x]. Returns (content, changes) tuple."""
    content = tasks_file.read_text()
    changes = []

    def replacer(m):
        prefix, ref, rest = m.group(1), m.group(2), m.group(3)
        if ref in refs:
            old_marker = "[~]" if "[~]" in prefix else "[ ]"
            changes.append(f"  task {ref}: {old_marker} → [x]")
            return prefix.replace(old_marker, "[x]") + ref + rest
        return m.group(0)

    new_content = OPEN_TASK_PATTERN.sub(replacer, content)
    if changes:
        tasks_file.write_text(new_content)
    return new_content, changes


def mark_tasks_in_progress(tasks_file: Path, refs: set[str]) -> tuple[str, list[str]]:
    """Mark matching unopened [ ] tasks as [~]. Skips already-[~] and [x] tasks."""
    content = tasks_file.read_text()
    changes = []

    def replacer(m):
        prefix, ref, rest = m.group(1), m.group(2), m.group(3)
        if ref in refs:
            changes.append(f"  task {ref}: [ ] → [~]")
            return prefix.replace("[ ]", "[~]") + ref + rest
        return m.group(0)

    new_content = UNOPENED_TASK_PATTERN.sub(replacer, content)
    if changes:
        tasks_file.write_text(new_content)
    return new_content, changes


def get_open_task_refs(content: str) -> set[str]:
    """Return refs for tasks that are open [ ] or in-progress [~]."""
    return set(re.findall(r"^\s*- \[[ ~]\] (?<!\d)([\d]+\.[\d]+)(?!\d)", content, re.MULTILINE))


def get_done_task_refs(content: str) -> set[str]:
    return set(DONE_TASK_PATTERN.findall(content))


def try_archive(change: str) -> bool:
    """Attempt to archive via openspec CLI. Returns True on success."""
    result = subprocess.run(
        ["openspec", "archive", change, "--yes"],
        capture_output=True, text=True, cwd=WORKSPACE
    )
    return result.returncode == 0


def main() -> int:
    tasks_files = find_tasks_files()
    if not tasks_files:
        return 0

    closed_issues = get_issues_by_status("closed")
    inprogress_issues = get_issues_by_status("in_progress")
    open_issues = get_issues_by_status("open") + inprogress_issues

    if not closed_issues and not inprogress_issues:
        return 0

    closed_refs_by_change = collect_task_refs_by_change(closed_issues)
    inprogress_refs_by_change = collect_task_refs_by_change(inprogress_issues)
    open_refs_by_change = collect_task_refs_by_change(open_issues)

    # All non-archived changes with tasks.md files
    active_changes = [f.parent.name for f in tasks_files]

    for tasks_file in tasks_files:
        change = tasks_file.parent.name

        closed_refs = resolve_refs_for_change(change, closed_refs_by_change, active_changes)
        inprogress_refs = resolve_refs_for_change(change, inprogress_refs_by_change, active_changes)
        open_refs_in_beads = resolve_refs_for_change(change, open_refs_by_change, active_changes)

        if not closed_refs and not inprogress_refs:
            continue

        header_printed = False

        # Step 1: closed beads → [x]  (overrides [~] if already marked)
        if closed_refs:
            try:
                content, changes = mark_tasks_complete(tasks_file, closed_refs)
            except (IOError, OSError) as e:
                print(f"[sync-openspec-tasks] Warning: could not process {tasks_file}: {e}")
                continue
            if changes:
                print(f"[sync-openspec-tasks] {change}/tasks.md updated:")
                for c in changes:
                    print(c)
                header_printed = True
        else:
            try:
                content = tasks_file.read_text()
            except (IOError, OSError) as e:
                print(f"[sync-openspec-tasks] Warning: could not read {tasks_file}: {e}")
                continue

        # Step 2: in_progress beads → [~]  (only [ ] tasks not already advanced)
        if inprogress_refs:
            try:
                content, ip_changes = mark_tasks_in_progress(tasks_file, inprogress_refs)
            except (IOError, OSError) as e:
                print(f"[sync-openspec-tasks] Warning: could not process {tasks_file}: {e}")
                continue
            if ip_changes:
                if not header_printed:
                    print(f"[sync-openspec-tasks] {change}/tasks.md updated:")
                    header_printed = True
                for c in ip_changes:
                    print(c)

        # Check completion
        open_task_refs = get_open_task_refs(content)
        done_task_refs = get_done_task_refs(content)
        all_task_refs = open_task_refs | done_task_refs

        if open_task_refs:
            continue  # Still work to do

        if not done_task_refs:
            continue  # No tasks at all

        # All tasks are [x] — assess confidence
        # High confidence: every done task has a matching closed bead,
        # and no open beads still reference this change.
        uncovered = done_task_refs - closed_refs          # [x] but no closed bead
        still_open = all_task_refs & open_refs_in_beads   # tasks with open beads

        high_confidence = (not uncovered) and (not still_open)

        if high_confidence:
            print(
                f"\n✓ All {len(done_task_refs)} OpenSpec tasks complete for '{change}' "
                f"(full Beads coverage). Auto-archiving..."
            )
            if try_archive(change):
                print(f"  Archived: openspec/changes/{change}/")
            else:
                print(
                    f"  Archive command failed — archive manually:\n"
                    f"  /openspec-archive-change {change}"
                )
        else:
            caveats = []
            if uncovered:
                caveats.append(
                    f"{len(uncovered)} task(s) marked [x] without a closed bead "
                    f"({', '.join(sorted(uncovered))})"
                )
            if still_open:
                caveats.append(
                    f"{len(still_open)} open bead(s) still reference tasks in this change"
                )
            print(
                f"\n⚠ All tasks show [x] for '{change}' but confidence is low:\n"
                + "\n".join(f"  - {c}" for c in caveats)
                + f"\n  Review and archive manually if ready: /openspec-archive-change {change}"
            )

    return 0


if __name__ == "__main__":
    sys.exit(main())
