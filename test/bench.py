#!/usr/bin/env python3
"""Quick quality/latency probe of the two servers through the same prompt builder the plugin uses.

Usage: test/bench.py [MAIN_URL FAST_URL]   (run it from a directory that looks like a project; history is simulated)
Flags a suggestion as REPEAT when a 3-word window appears twice, and LONG when it is over 60 characters.
"""
import os, subprocess, sys, time, statistics
HERE = os.path.dirname(os.path.abspath(__file__))
QUERY = os.path.join(HERE, "..", "lib", "query.py")
MAIN = sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8765/infill"
FAST = sys.argv[2] if len(sys.argv) > 2 else "http://localhost:8766/infill"
HIST = "git status\ngo test ./...\nls src\ndocker ps\ncd docs\n"
COMPLETE = ["git ", "git log --", "git commit -m ", "docker run -", "docker compose u", "ls -", "cd ", "tar -x",
            "find . -name '*.go' -", "grep -r", "kubectl get po", "npm run ", "ssh -", "curl -s localhost:8080/"]
REQUEST = ["show me the biggest files here", "undo the last commit but keep the changes", "find which process is using port 8080",
           "compress the docs folder into a tar.gz", "count lines of go code", "list git branches sorted by last commit",
           "mostre os arquivos desta pasta", "qual processo esta usando a porta 3000", "comprimir a pasta src em zip",
           "remove todos os containers parados"]
def ask(mode, buf, url):
    env = dict(os.environ, ZLG_MODE=mode)
    t = time.time()
    out = subprocess.run([sys.executable, QUERY, url, buf, "40"], input=HIST, capture_output=True, text=True, env=env).stdout
    return out, (time.time() - t) * 1000
def flags(s):
    w = s.split(); seen = set(); rep = False
    for i in range(len(w) - 2):
        k = tuple(w[i:i + 3]); rep = rep or k in seen; seen.add(k)
    return ("REPEAT " if rep else "") + ("LONG" if len(s) > 60 else "")
def run(title, mode, bufs, url):
    print(f"== {title}"); ms = []
    for b in bufs:
        out, t = ask(mode, b, url); ms.append(t)
        print(f"{t:6.0f} ms  {b[:42]!r:46} -> {out[:70]!r} {flags(out)}")
    print(f"   median {statistics.median(ms):.0f} ms, max {max(ms):.0f} ms\n")
run("completion, fast model (0.5B)", "complete", COMPLETE, FAST)
run("completion, main model (1.5B)", "complete", COMPLETE, MAIN)
run("request -> command, main model (1.5B)", "request", REQUEST, MAIN)
