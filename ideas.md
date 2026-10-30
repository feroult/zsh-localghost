# Ideas

Collected from reading other projects. Status: nothing here is implemented yet. "Verified" below means I read the
project's own README; everything else comes from search-result summaries and should be checked in the repo before relying on it.

## Prior art (so we do not rebuild what exists)

| Project | What it does | Local model? | Source |
|---|---|---|---|
| ghst (insprd/ghst) | ghost text as you type, Ctrl+G natural language, Ctrl+R history search, Python daemon over a Unix socket | no: `openai` or `anthropic` only; "local model support (Ollama, LM Studio)" is on its roadmap | PyPI README, verified |
| zsh-ai-cmd (kylesnowschwartz) | natural language to command, ghost text on a hotkey (Ctrl+Z), Tab/→ accepts | yes, through Ollama (you run it); also an OpenAI-compatible URL setting | README, verified by a fetch agent |
| ai-prompt (mattapperson) | ghost text after Enter; skips the model when the input already looks like a command | no: OpenRouter only | README, verified by a fetch agent |
| ghosttype (trknhr) | next-command prediction, hotkey + list, no inline ghost text | yes, Ollama only (you run it); its README admits ~800 ms | pkg.go.dev README, verified by a fetch agent |
| zsh-ollama-command (plutowang) | description + hotkey, fzf picker | yes, Ollama only | README, verified by a fetch agent |
| llm-cmd-comp-qwen | Ctrl+K replaces the buffer with a generated command; `llm term` generates and runs | via the `llm` tool + a llama.cpp server you set up | PyPI README, verified |
| zsh-llm-suggestions (stefanheule) | description to command | no: OpenAI / Copilot | search summary only (name is nearly the same as this project's first name) |
| pi-shell-autocomplete (Termina1) | ghost text from a local FIM model | probably yes | search summary only: **read this repo first**, it may be the closest to this project |

What none of the verified ones offer: a ready-made local inference container that pulls and starts itself (CPU or GPU, no Ollama, no key).

## Ideas to adopt, in priority order

1. **Suggest while typing**, with a debounce (ghst: 200 ms, minimum 3 characters). The biggest UX gap today (we only answer Ctrl+Space).
   Needs an async query that is cancelled when you keep typing (`zle -F` on a background `curl`; no daemon needed). Use the 0.5B for this.
2. **Accept by parts and dismiss**: Shift+→ takes one word, Esc dismisses (ghst). Cheap.
3. **Undo after accepting**: Ctrl+Z restores what you had typed before accepting (ghst). Protects against accepting by accident.
4. **More context in the prompt**: exit status of the last command, project type from marker files (`package.json`, `go.mod`, `Dockerfile`...),
   active virtualenv, real branch names. Today we send cwd, first 20 files, current branch, last 8 history lines.
5. **"Thinking" indicator** while waiting (ghst has a spinner). Today nothing is shown for 0.2-2 s.
6. **Skip the model when history already has the answer** (ai-prompt). Saves CPU, and keeps typing fast.
7. **Cheat sheet** on a key (ghst uses Ctrl+/) for discoverability.
8. **Fix suggestions after a failed command** as ghost text (ghst roadmap). With a FIM model: put the failed command and its error in the prompt.
9. **Strip secrets from the history before building the prompt** (ghst does). Less important while everything stays local.
10. **Degrade gracefully when the server is down**: fall back to history only (pi-shell-autocomplete reportedly works without its model; unverified).

## Not to copy

- A Python daemon with a Unix socket (ghst): heavier than needed. A container plus `curl` is enough, and `zle -F` handles the async part.
- Executing generated commands directly (llm-cmd-comp-qwen's `llm term`): here nothing runs without Enter, and destructive-looking suggestions need a second Enter.

## Open questions

- Does ghst allow a custom base URL for its provider? If it does, the inference container could serve ghst and this plugin may be unnecessary.
  (Read `src/ghst/llm.py` and `config/default.toml` in its repo.)
- Quality: the 1.5B copies the history for vague requests (`mostre os arquivos desta pasta` gave `du -h ...`). Needs a small evaluation set before claiming anything.
- Name: settled on `zsh-localghost` (localhost + ghost text). The first working name was nearly identical to an existing project (zsh-llm-suggestions).

## Findings from the end-to-end test (2026-10-30) and what they change

Measured on an idle machine, 14 completion buffers and 10 requests (`test/bench.py`):

| | median | worst | notes |
|---|---|---|---|
| completion, 0.5B | 67-78 ms | ~500 ms | wrong or invented on ~half of the buffers (`git log --` gave `start`; `ssh -` invented an IP) |
| completion, 1.5B | 156-224 ms | 1.3 s | sensible on common tools; `ssh`, `kubectl` unreliable |
| request -> command, 1.5B | 318-441 ms | ~600 ms | after the changes below: 10/10 plausible (was 8/10) |

Changes made because of it: the 1.5B now handles completion (the 0.5B is opt-in via `ZLG_URL_FAST`); three fixed request->command
examples before the request (stopped it copying the history: "qual processo esta usando a porta 3000" had given `docker ps -a`);
repeat penalty only for requests (it made completion worse); repeated options are trimmed; only the last two components of the cwd
go into the prompt (the 0.5B copied a temp path and a UUID into suggestions); the destructive-command list went from 5 patterns to
~45 with word boundaries (`git checkout -- .` used to run on the first Enter); the container exits 0 on `stop`.

## Possible evolutions (not started)

Adoption blockers first.

1. **arm64 image** (Apple-silicon Macs are most of the zsh audience). Needs `docker/setup-qemu-action` or native arm runners, and a base image with an arm64 manifest (not checked).
2. **A no-container mode.** On macOS a container cannot use Metal and is slower than a native `llama-server`; offer `ZLG_BACKEND=native` that runs
   a local `llama-server` (brew) and the same `-hf` models, and a documented way to point at an existing Ollama / llama-server (Ollama's FIM API differs: `/api/generate` with `suffix`).
3. **Auto-retry after the first start.** Today the first Ctrl+Space says "try again in a moment". Watch the container with `zle -F` and fill the suggestion in when it is ready, with a progress hint while the weights download (~2 GB).
4. **`zlg doctor`.** Checks the engine, port conflicts, `python3`/`curl`, zsh >= 5.9, UTF-8 locale and colours, and fixes `zlg status` (it queries `localhost`, which is wrong when the engine is remote, as in this sandbox: add `ZLG_HOST`).
5. **Packaging and docs:** plugin-manager instructions tested (oh-my-zsh, zinit, antidote, sheldon), a Homebrew formula, a short demo GIF, a Windows/WSL note.

Quality and experience.

6. **Suggest while typing** (idea 1 above). The 1.5B median of ~160 ms is enough for a 200 ms debounce; the 0.5B is not accurate enough. Needs the async query with cancellation.
7. **Project-aware context:** `package.json` scripts, `Makefile` targets, `docker-compose` services, git branch names, last exit code. `npm run ` and `make ` should complete with names that exist.
8. **Retrieve from the whole history** instead of the last 8 lines (prefix match first, semantic later); strip secrets before building the prompt.
9. **A scored evaluation set** (does the command run, does it match) so model, quantisation and prompt changes can be compared; try Q4 for speed, other small FIM models, and a larger model on request only.
10. **Explain key** (what does this command do) and **fix-after-failure** suggestions using the error output.
11. **Accept by word** (Shift+Right), **Esc** to dismiss, **undo** after accepting, a **cheat sheet** key.

Operations and safety.

12. **Idle shutdown:** stop the container after N idle minutes and let the transparent start bring it back (~2 s with warm volume), to give the ~450 MB back.
13. **Pin the model revisions** (the `-hf` pull takes the latest of each repo) and offer a `:full` image with the weights baked in for offline machines.
14. **CI tests:** run `test/destructive_test.zsh` and shellcheck before building the image; check the published image really carries the HEALTHCHECK (OCI output may drop it).
15. **Access control:** llama-server has no auth; bound to 127.0.0.1 by default, but other local users can query it. An API key or a unix socket would close that.
16. **Key bindings:** Ctrl+Space is not delivered by every terminal; Ctrl+Enter is indistinguishable from Enter in many; document a tested fallback.
