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
