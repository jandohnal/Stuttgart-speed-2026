"""Count how the game was made, for the credits in the main menu.

Sources (both local, nothing from the original game):
- git history of the repository: first and last commit, number of commits;
- Claude Code session logs of the project (~/.claude/projects/<project>/*.jsonl,
  subagents in <session>/subagents/*.jsonl): every API response carries its
  token usage. A response written as several log lines (one per content block)
  shares one message id and is counted once.

Active time: the gaps between consecutive responses, summed where a gap is under
IDLE minutes (a longer pause counts as a break).

Output JSON:
    {"updated": "YYYY-MM-DD", "first_commit": "YYYY-MM-DD", "last_commit": ...,
     "days": N, "commits": N, "sessions": N, "responses": N, "active_hours": h,
     "tokens": {"input": N, "cache_write": N, "cache_read": N, "output": N, "total": N},
     "models": {"claude-opus-5-5": N, ...}}

Usage:
    python3 tools/credits_stats.py game/ui/credits_stats.json [--logs <dir>]
"""
import datetime
import glob
import json
import os
import subprocess
import sys

IDLE = 30  # minutes


def project_log_dir(repo):
    """Claude Code keeps a project's logs under its path with / \\ : and . replaced by -."""
    name = os.path.abspath(repo).replace("/", "-").replace("\\", "-").replace(":", "-").replace(".", "-")
    return os.path.join(os.path.expanduser("~/.claude/projects"), name)


def git_stats(repo):
    dates = subprocess.run(["git", "-C", repo, "log", "--format=%ad", "--date=short"],
                           capture_output=True, text=True, check=True).stdout.split()
    return {"first_commit": min(dates), "last_commit": max(dates), "commits": len(dates)}


def log_stats(log_dir):
    tokens = {"input": 0, "cache_write": 0, "cache_read": 0, "output": 0}
    models = {}
    seen = set()
    times = []
    sessions = len(glob.glob(os.path.join(log_dir, "*.jsonl")))
    files = glob.glob(os.path.join(log_dir, "*.jsonl")) + glob.glob(os.path.join(log_dir, "*", "subagents", "*.jsonl"))
    for path in files:
        with open(path, encoding="utf-8") as f:
            for line in f:
                if '"usage"' not in line:
                    continue
                try:
                    entry = json.loads(line)
                except json.JSONDecodeError:
                    continue
                message = entry.get("message")
                if not isinstance(message, dict) or not isinstance(message.get("usage"), dict):
                    continue
                key = message.get("id") or entry.get("requestId") or entry.get("uuid")
                if key in seen:
                    continue
                seen.add(key)
                usage = message["usage"]
                tokens["input"] += usage.get("input_tokens") or 0
                tokens["cache_write"] += usage.get("cache_creation_input_tokens") or 0
                tokens["cache_read"] += usage.get("cache_read_input_tokens") or 0
                tokens["output"] += usage.get("output_tokens") or 0
                model = message.get("model") or "unknown"
                if not model.startswith("<"):
                    models[model] = models.get(model, 0) + 1
                if entry.get("timestamp"):
                    times.append(datetime.datetime.fromisoformat(entry["timestamp"].replace("Z", "+00:00")))
    times.sort()
    gaps = [(b - a).total_seconds() for a, b in zip(times, times[1:])]
    active = sum(gap for gap in gaps if gap < IDLE * 60)
    tokens["total"] = sum(tokens.values())
    return {"sessions": sessions, "responses": len(seen), "active_hours": round(active / 3600, 1),
            "tokens": tokens, "models": dict(sorted(models.items(), key=lambda m: -m[1]))}


def main():
    args = sys.argv[1:]
    if not args:
        sys.exit(__doc__)
    out = args[0]
    repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    log_dir = args[args.index("--logs") + 1] if "--logs" in args else project_log_dir(repo)
    stats = {"updated": datetime.date.today().isoformat()}
    stats.update(git_stats(repo))
    first = datetime.date.fromisoformat(stats["first_commit"])
    stats["days"] = (datetime.date.today() - first).days + 1
    stats.update(log_stats(log_dir))
    with open(out, "w", encoding="utf-8") as f:
        json.dump(stats, f, indent=1)
        f.write("\n")
    t = stats["tokens"]
    print(f"{stats['days']} days, {stats['commits']} commits, {stats['sessions']} sessions, "
          f"{stats['active_hours']} h active, {t['total']:,} tokens ({t['output']:,} output) -> {out}")


if __name__ == "__main__":
    main()
