# zsh-localghost

A tiny, self-contained local LLM that haunts your zsh prompt: ghost-text suggestions from a small model running
**locally in a container** (CPU only, no GPU, no API key, nothing leaves your machine).
Press **Ctrl+Space**:

- on part of a command (`git log --`) it completes it, as ghost text;
- on plain words (`show me the biggest files here`) it writes the command (`→ du -h --max-depth=1 | sort -hr | head -n 10`).

**Ctrl+F** accepts a suggestion, **Enter** accepts it and runs it (a command that looks destructive, such as `rm -r` or
`git reset --hard`, only goes into the buffer: a second Enter runs it). Nothing runs unless you press Enter.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/feroult/zsh-localghost/main/install.sh | sh
```

It clones the plugin into `~/.zsh/zsh-localghost` and adds one marked block at the end of your `~/.zshrc`
(it has to come after zsh-autosuggestions). No sudo. Open a new terminal and press Ctrl+Space. To remove it all:
`sh ~/.zsh/zsh-localghost/install.sh --uninstall`. To read the script before running it: open `install.sh` in this repo (about 70 lines).

<details><summary>By hand, or with a plugin manager</summary>

```zsh
git clone https://github.com/feroult/zsh-localghost ~/.zsh/zsh-localghost
# in ~/.zshrc, AFTER zsh-autosuggestions if you use it:
source ~/.zsh/zsh-localghost/zsh-localghost.plugin.zsh
```

Plugin managers (not tested): `zinit light feroult/zsh-localghost`, `antidote` / `sheldon` with `feroult/zsh-localghost`;
load it after zsh-autosuggestions.
</details>

Needs `zsh` >= 5.9, `curl`, `python3`, and `podman` or `docker`.

**The installer starts the model server for you** (`bin/zlg start`): it pulls the ~860 MB image and returns, and the container then
downloads ~2 GB of weights from Hugging Face into a volume in the background (about a minute on a fast line). The container is created
with `--restart unless-stopped`, so your engine brings it back after a restart; the weights stay in the `zsh-localghost-models` volume.
If you press Ctrl+Space before it has finished, you get no suggestion yet: wait a little and press it again.
`install.sh --no-start` skips this; the first Ctrl+Space then starts the server instead (and that first press only starts it).

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
| `ZLG_URL` | `http://localhost:31865/infill` | main server (1.5B): completing and writing commands |
| `ZLG_URL_FAST` | unset | optional 0.5B server (`http://localhost:31866/infill`) for completion only: ~2x faster, clearly less accurate |
| `ZLG_AUTOSTART` | `1` | `0` = never start the container for you |
| `ZLG_PULL_ARGS` | | extra flags for `pull` and `run` (e.g. `--tls-verify=false` for a plain-HTTP registry), read by `bin/zlg` |
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

Verified (2026-10-30, including `curl ... | sh` straight from this repo, WSL2 + rootful podman, Debian/Ubuntu, zsh 5.9, latest zsh-autosuggestions), as a new user would install it:
- the image published by the workflow pulls from ghcr.io; the first Ctrl+Space starts the container, downloads the weights into an
  empty volume and the next Ctrl+Space answers (~55 s in total on this machine); a stopped container is restarted the same way;
- completing a command, writing a command from words (English and Portuguese), Ctrl+F / Enter, the second-Enter rule for
  destructive suggestions, coexistence with zsh-autosuggestions, `ZLG_ENTER=0`, quotes and special characters in the buffer;
- idle cost of the container: ~3-4 % of a CPU and ~450 MB of RAM.

Tests you can run: `test/bench.py` (latency and sanity of completion and request mode against your servers),
`zsh test/destructive_test.zsh test/destructive_cases.txt` (the destructive-command rules), `test/lab.sh` (a throwaway Ubuntu lab).

Not verified: running the arm64 image (it is published for linux/amd64 and linux/arm64, but only amd64 was ever run), plugin managers (oh-my-zsh, zinit...), zsh older than 5.9, terminals other than the one used for testing,
GPU, macOS. Quality is that of a 1.5B model: good for common commands (`git`, `docker`, `tar`, `find`), unreliable for rarely used ones
(`ssh`, `kubectl`). Read before pressing Enter.

## Licenses

The code is yours to license (none chosen yet). The models are downloaded from Hugging Face and keep their own licenses
(check the Qwen2.5-Coder model cards before redistributing anything).
