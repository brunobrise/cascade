#!/usr/bin/env python3
"""
tools/semver.py - Strict Sequential SemVer 2.0.0 Engine for Cascade

Handles conventional commit validation, sequential version bumping from 0.0.0,
git tag management, and Lefthook post-commit / commit-msg hook integration.
"""

import sys
import os
import re
import subprocess
from typing import Tuple, Optional, List

CONVENTIONAL_REGEX = re.compile(
    r"^(?P<type>feat|fix|perf|refactor|docs|test|build|ci|chore|style)"
    r"(?:\((?P<scope>[^\)]+)\))?"
    r"(?P<breaking>!)?"
    r":\s*(?P<subject>.+)$"
)

def parse_semver(v_str: str) -> Tuple[int, int, int]:
    v_clean = v_str.strip().lstrip("v")
    parts = v_clean.split(".")
    if len(parts) != 3:
        raise ValueError(f"Invalid SemVer string: {v_str}")
    return int(parts[0]), int(parts[1]), int(parts[2])

def format_semver(major: int, minor: int, patch: int) -> str:
    return f"{major}.{minor}.{patch}"

def is_breaking_change(commit_msg: str) -> bool:
    lines = commit_msg.strip().splitlines()
    first_line = lines[0] if lines else ""
    m = CONVENTIONAL_REGEX.match(first_line)
    if m and m.group("breaking") == "!":
        return True
    for line in lines:
        if line.startswith("BREAKING CHANGE:") or line.startswith("BREAKING-CHANGE:"):
            return True
    return False

def get_commit_type(commit_msg: str) -> Optional[str]:
    first_line = commit_msg.strip().splitlines()[0] if commit_msg.strip() else ""
    m = CONVENTIONAL_REGEX.match(first_line)
    return m.group("type") if m else None

def bump_version(current: Tuple[int, int, int], commit_msg: str) -> Tuple[int, int, int]:
    major, minor, patch = current
    if is_breaking_change(commit_msg):
        return major + 1, 0, 0
    ctype = get_commit_type(commit_msg)
    if ctype == "feat":
        return major, minor + 1, 0
    # fix, perf, refactor, docs, chore, test, style, ci, build
    return major, minor, patch + 1

def run_git(args: List[str], check: bool = True) -> str:
    res = subprocess.run(["git"] + args, capture_output=True, text=True, check=check)
    return res.stdout.strip()

def get_latest_tag_version() -> Optional[Tuple[int, int, int]]:
    tags = run_git(["tag", "-l", "v*"], check=False).splitlines()
    semver_tags = []
    for t in tags:
        try:
            semver_tags.append(parse_semver(t))
        except ValueError:
            continue
    if not semver_tags:
        return None
    semver_tags.sort()
    return semver_tags[-1]

def replay_history() -> List[Tuple[str, str, str]]:
    log = run_git(["log", "--reverse", "--pretty=format:%H%x09%s"])
    if not log:
        return []
    lines = log.splitlines()
    major, minor, patch = 0, 0, 0
    history = []
    for line in lines:
        parts = line.split("\t", 1)
        chash = parts[0]
        subj = parts[1] if len(parts) > 1 else ""
        major, minor, patch = bump_version((major, minor, patch), subj)
        v_str = format_semver(major, minor, patch)
        history.append((chash, v_str, subj))
    return history

def get_current_version() -> str:
    # 1. Check VERSION file
    v_file = os.path.join(os.path.dirname(__file__), "..", "VERSION")
    if os.path.isfile(v_file):
        with open(v_file, "r") as f:
            content = f.read().strip()
            if content:
                return content
    # 2. Check latest tag
    latest = get_latest_tag_version()
    if latest:
        return format_semver(*latest)
    # 3. Calculate from history
    history = replay_history()
    if history:
        return history[-1][1]
    return "0.0.0"

def cmd_tag_history():
    history = replay_history()
    print(f"Replaying {len(history)} commits from 0.0.0...")
    for chash, v_str, subj in history:
        tag_name = f"v{v_str}"
        # Check if tag already exists pointing to this commit
        existing = run_git(["tag", "-l", tag_name], check=False)
        if not existing:
            run_git(["tag", "-a", tag_name, chash, "-m", tag_name])
            print(f"  Tagged {chash[:7]} as {tag_name}: {subj[:55]}")
        else:
            print(f"  Already tagged {tag_name} on {chash[:7]}")
    if history:
        latest = history[-1][1]
        v_file = os.path.join(os.path.dirname(__file__), "..", "VERSION")
        with open(v_file, "w") as f:
            f.write(latest + "\n")
        print(f"History tagged successfully. Current version: {latest}")

def cmd_check_msg(msg_file: str):
    if not os.path.isfile(msg_file):
        print(f"Error: Commit message file '{msg_file}' not found.", file=sys.stderr)
        sys.exit(1)
    with open(msg_file, "r", encoding="utf-8") as f:
        lines = [l for l in f.read().splitlines() if not l.strip().startswith("#")]
    if not lines or not lines[0].strip():
        print("Error: Empty commit message.", file=sys.stderr)
        sys.exit(1)
    first_line = lines[0].strip()
    m = CONVENTIONAL_REGEX.match(first_line)
    if not m:
        print("\n============================================================", file=sys.stderr)
        print("Lefthook Error: Invalid Conventional Commit Message!", file=sys.stderr)
        print("------------------------------------------------------------", file=sys.stderr)
        print(f"  Your commit: \"{first_line}\"", file=sys.stderr)
        print("\nFormat must follow:", file=sys.stderr)
        print("  <type>[optional scope][!]: <description>", file=sys.stderr)
        print("\nAllowed types:", file=sys.stderr)
        print("  feat, fix, perf, refactor, docs, test, chore, build, ci, style", file=sys.stderr)
        print("\nExamples:", file=sys.stderr)
        print("  feat: add multi-column screen splits for ultrawide displays", file=sys.stderr)
        print("  fix: prevent window overlap on secondary monitor", file=sys.stderr)
        print("  feat!: redesign entire window cascade architecture", file=sys.stderr)
        print("============================================================\n", file=sys.stderr)
        sys.exit(1)
    print(f"[Lefthook] Valid Conventional Commit: {first_line}")

def cmd_post_commit():
    # Read HEAD commit
    head_hash = run_git(["rev-parse", "HEAD"])
    head_msg = run_git(["log", "-1", "--pretty=%B"])
    head_tags = run_git(["tag", "--points-at", "HEAD"], check=False).splitlines()

    for t in head_tags:
        if t.startswith("v"):
            try:
                parse_semver(t)
                print(f"[Lefthook] HEAD {head_hash[:7]} already tagged as {t}")
                return
            except ValueError:
                pass

    # Determine previous version from parent commit
    parent_tag = run_git(["describe", "--tags", "--abbrev=0", "HEAD~1"], check=False)
    if parent_tag:
        try:
            prev = parse_semver(parent_tag)
        except ValueError:
            prev = (0, 0, 0)
    else:
        # Fallback to history replay up to HEAD^
        history = replay_history()
        prev = (0, 0, 0)
        for chash, v_str, _ in history:
            if chash == head_hash:
                break
            prev = parse_semver(v_str)

    next_v = bump_version(prev, head_msg)
    next_str = format_semver(*next_v)
    tag_name = f"v{next_str}"

    # Tag HEAD
    run_git(["tag", "-a", tag_name, "HEAD", "-m", tag_name])

    # Update VERSION file
    v_file = os.path.join(os.path.dirname(__file__), "..", "VERSION")
    with open(v_file, "w") as f:
        f.write(next_str + "\n")

    print(f"[Lefthook] Version bumped: v{format_semver(*prev)} -> {tag_name} on {head_hash[:7]}")

def main():
    if len(sys.argv) < 2:
        print("Usage: semver.py [current|next|replay|tag-history|check-msg <file>|post-commit]")
        sys.exit(1)
    cmd = sys.argv[1]
    if cmd == "current":
        print(get_current_version())
    elif cmd == "next":
        curr = parse_semver(get_current_version())
        msg = sys.argv[2] if len(sys.argv) > 2 else "feat: new feature"
        nxt = bump_version(curr, msg)
        print(format_semver(*nxt))
    elif cmd == "replay":
        history = replay_history()
        print(f"Replay from 0.0.0 ({len(history)} commits):")
        for chash, v_str, subj in history:
            print(f"  {chash[:7]} -> v{v_str:<7} {subj}")
    elif cmd == "tag-history":
        cmd_tag_history()
    elif cmd == "check-msg":
        if len(sys.argv) < 3:
            print("Error: Commit message file required", file=sys.stderr)
            sys.exit(1)
        cmd_check_msg(sys.argv[2])
    elif cmd == "post-commit":
        cmd_post_commit()
    else:
        print(f"Unknown command: {cmd}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
