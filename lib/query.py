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
    lines.append("# cwd: " + os.getcwd().replace(os.path.expanduser("~"), "~", 1))
    names = sorted(os.listdir("."))[:20]
    lines.append("# files: " + "  ".join(n + "/" if os.path.isdir(n) else n for n in names))
    branch = run(["git", "branch", "--show-current"]).strip()
    if branch:
        dirty = len(run(["git", "status", "--porcelain"]).splitlines())
        lines.append("# git branch: %s (%d files modified)" % (branch, dirty))
    return "\n".join(lines) + "\n"

def main():
    url, buf = sys.argv[1], sys.argv[2]
    n = int(sys.argv[3]) if len(sys.argv) > 3 else 40
    hist = [l.strip() for l in sys.stdin.read().splitlines() if l.strip()][-8:]
    prefix = context() + "".join("$ %s\n" % h for h in hist)
    if os.environ.get("ZLG_MODE") == "request":
        prefix += "# " + buf.strip() + "\n$ "
    else:
        prefix += "$ " + buf
    body = json.dumps({"input_prefix": prefix, "input_suffix": "", "n_predict": n, "temperature": 0,
                       "stop": ["\n"], "cache_prompt": True}).encode()
    try:
        req = urllib.request.Request(url, body, {"Content-Type": "application/json"})
        print(json.load(urllib.request.urlopen(req, timeout=4))["content"], end="")
    except Exception as e:
        print("", end="")
        print("fim_query: %s" % e, file=sys.stderr)

main()
