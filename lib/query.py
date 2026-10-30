#!/usr/bin/env python3
"""Builds a context-rich FIM prompt and asks a llama-server /infill endpoint for a shell suggestion.

Usage: query.py URL BUFFER [N_PREDICT]   (recent history lines on stdin, oldest first)
Prints only the suggestion (no newline). With ZLG_MODE=request the buffer is a natural-language request: the command is generated on the line below it
(otherwise the buffer is a command line to complete).
"""
import json, os, subprocess, sys, urllib.request

def run(cmd, timeout=0.5):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout).stdout
    except Exception:
        return ""

def context():
    lines = ["# host: %s, shell: zsh" % (os.uname().sysname.lower())]
    # only the last two path components: long paths (UUIDs, temp dirs) get copied into suggestions by small models
    parts = os.getcwd().replace(os.path.expanduser("~"), "~", 1).split("/")
    lines.append("# cwd: " + ("\u2026/" + "/".join(parts[-2:]) if len(parts) > 3 else "/".join(parts)))
    names = sorted(os.listdir("."))[:20]
    lines.append("# files: " + "  ".join(n + "/" if os.path.isdir(n) else n for n in names))
    branch = run(["git", "branch", "--show-current"]).strip()
    if branch:
        dirty = len(run(["git", "status", "--porcelain"]).splitlines())
        lines.append("# git branch: %s (%d files modified)" % (branch, dirty))
    return "\n".join(lines) + "\n"

# A few fixed request->command pairs placed before the real request: they show the format and stop the model from
# copying the history when the request is vague (measured: "remove todos os containers parados" used to give "docker ps -a").
EXAMPLES = (
    "# list files by size, biggest first\n$ ls -lS\n"
    "# show which process listens on port 8080\n$ lsof -i :8080\n"
    "# mostre as ultimas 5 linhas de app.log\n$ tail -n 5 app.log\n"
)

def trim_repeats(s):
    """Cut the suggestion where an option (-x / --xyz) shows up a second time: small models loop on flags."""
    words, seen, out = s.split(" "), set(), []
    for w in words:
        if w.startswith("-") and w in seen:
            break
        seen.add(w); out.append(w)
    return " ".join(out).rstrip()

def main():
    url, buf = sys.argv[1], sys.argv[2]
    n = int(sys.argv[3]) if len(sys.argv) > 3 else 40
    hist = [l.strip() for l in sys.stdin.read().splitlines() if l.strip()][-8:]
    prefix = context() + "".join("$ %s\n" % h for h in hist)
    if os.environ.get("ZLG_MODE") == "request":
        prefix += EXAMPLES + "# " + buf.strip() + "\n$ "
    else:
        prefix += "$ " + buf
    body = json.dumps({"input_prefix": prefix, "input_suffix": "", "n_predict": n, "temperature": 0,
                       "stop": ["\n"], "cache_prompt": True,
                       # a repeat penalty helps requests (stops copying the history) but hurts completion (it avoids reusing paths/flags)
                       "repeat_penalty": 1.15 if os.environ.get("ZLG_MODE") == "request" else 1.0}).encode()
    try:
        req = urllib.request.Request(url, body, {"Content-Type": "application/json"})
        print(trim_repeats(json.load(urllib.request.urlopen(req, timeout=4))["content"]), end="")
    except Exception as e:
        print("", end="")
        print("fim_query: %s" % e, file=sys.stderr)

main()
