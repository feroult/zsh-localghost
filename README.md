# zsh-localghost

A tiny, self-contained local LLM that haunts your zsh prompt: ghost-text suggestions from a small model running
**locally in a container** (CPU only, no GPU, no API key, nothing leaves your machine).
Press **Ctrl+Space**:

- on part of a command (`git log --`) it completes it, as ghost text;
- on plain words (`show me the biggest files here`) it writes the command (`→ du -h --max-depth=1 | sort -hr | head -n 10`).

**Ctrl+F** accepts a suggestion, **Enter** accepts it and runs it (a command that looks destructive, such as `rm -r` or
`git reset --hard`, only goes into the buffer: a second Enter runs it). Nothing runs unless you press Enter.

## Install

```zsh
git clone https://github.com/feroult/zsh-localghost ~/.zsh/zsh-localghost
# in ~/.zshrc, AFTER zsh-autosuggestions if you use it:
source ~/.zsh/zsh-localghost/zsh-localghost.plugin.zsh
```

Needs `zsh` >= 5.9, `curl`, `python3`, and `podman` or `docker`. The first suggestion starts the inference container
(`bin/zlg start`: pulls the image, then downloads ~2 GB of weights from Hugging Face into a volume) and tells you to retry in a moment.

## How it is put together

```
zsh-localghost.plugin.zsh   the widget: key bindings, ghost text, colours, Enter handling, auto-start
lib/query.py                 builds the prompt (cwd, files, git branch, recent history) and calls /infill
bin/zlg                      start | stop | status | logs | pull for the container
server/                      the image: two llama.cpp servers (Qwen2.5-Coder 1.5B on :8080, 0.5B on :8081), CPU only
.github/workflows/publish.yml  builds the image and pushes ghcr.io/<owner>/zsh-localghost
test/lab.sh                  throwaway Ubuntu container with zsh + autosuggestions + the plugin, to try it safely
```

The image does not contain the weights: they are fetched from Hugging Face on first start into the `zsh-localghost-models` volume.
Build it with `podman build --format docker server/` (the HEALTHCHECK is dropped in OCI format).

## Settings (export before sourcing)

| Variable | Default | |
|---|---|---|
| `ZLG_URL` / `ZLG_URL_FAST` | `localhost:8765` / `:8766` (`/infill`) | main (1.5B) and fast (0.5B, line completion) servers |
| `ZLG_AUTOSTART` | `1` | `0` = never start the container for you |
| `ZLG_ENTER` | `1` | `0` = leave Enter alone |
| `ZLG_ARROW`, `ZLG_WARN_MARK` | ` → `, `⚠ destructive?` | glyphs (ASCII fallback when the locale is not UTF-8) |
| `ZLG_STYLE_COMPLETE/COMMAND/ARROW/WARN` | greys, lavender, coral | `region_highlight` styles (256-colour numbers; basic colours if the terminal has fewer) |
| `ZLG_KEY` | | extra key sequence that triggers a suggestion |
| `ZLG_IMAGE`, `ZLG_PORT`, `ZLG_PORT_FAST`, `ZLG_BIND`, `ZLG_VOLUME`, `ZLG_THREADS` | | for `bin/zlg` |

`Ctrl+X Ctrl+R` forces "write a command" mode when the guess between completing and writing was wrong.

## Privacy

The prompt contains your current directory, the first file names in it, the git branch and your last 8 history lines.
It goes only to the local container (published on 127.0.0.1 by default). Nothing leaves your machine except the one-time model download.

## Status: what is and is not verified

Verified on one machine (WSL2 + rootful podman, Ubuntu 24.04 lab container, latest zsh-autosuggestions):
completion, command generation, Enter/Ctrl+F handling, colours and glyphs, the image building and serving both models from a populated volume.

Not verified: the GitHub workflow (amd64 image only), arm64, pulling the image from ghcr.io (the package must be made public first), plugin managers (oh-my-zsh, zinit...),
the auto-start path from inside a real zsh session, zsh older than 5.9, terminals other than the one used for testing.
Suggestion quality is that of a 0.5B/1.5B model: it often copies your history and can be wrong. Read before pressing Enter.

## Licenses

The code is yours to license (none chosen yet). The models are downloaded from Hugging Face and keep their own licenses
(check the Qwen2.5-Coder model cards before redistributing anything).
