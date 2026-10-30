#!/bin/sh
# zsh-localghost installer.  Usage:
#   curl -fsSL https://raw.githubusercontent.com/feroult/zsh-localghost/main/install.sh | sh
#   sh install.sh --uninstall        remove the block from your .zshrc and the install directory
#   sh install.sh --pull             also pre-download the model server image (~860 MB) instead of waiting for the first use
# Environment: ZLG_HOME (install dir, default ~/.zsh/zsh-localghost), ZLG_REPO (git url to clone), ZDOTDIR (where .zshrc lives).
# It only touches ZLG_HOME and one marked block at the end of your .zshrc. No sudo, no system changes.
set -e

REPO="${ZLG_REPO:-https://github.com/feroult/zsh-localghost}"
DIR="${ZLG_HOME:-$HOME/.zsh/zsh-localghost}"
RC="${ZDOTDIR:-$HOME}/.zshrc"
BEGIN="# >>> zsh-localghost >>>"
END="# <<< zsh-localghost <<<"

say() { printf '%s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

remove_block() {
  [ -f "$RC" ] && grep -qF "$BEGIN" "$RC" || return 0
  tmp="$RC.zlg.$$"
  awk -v b="$BEGIN" -v e="$END" '$0==b{skip=1} !skip{print} $0==e{skip=0}' "$RC" > "$tmp" && cat "$tmp" > "$RC" && rm -f "$tmp"
  say "removed the zsh-localghost block from $RC"
}

if [ "$1" = "--uninstall" ]; then
  remove_block
  # only delete a directory that really is an install of this project
  if [ -f "$DIR/lib/query.py" ] && [ -f "$DIR/zsh-localghost.plugin.zsh" ]; then
    rm -rf -- "$DIR" && say "removed $DIR"
  fi
  have podman && podman rm -f zsh-localghost >/dev/null 2>&1 || true
  have docker && docker rm -f zsh-localghost >/dev/null 2>&1 || true
  say "done. The downloaded models stay in the 'zsh-localghost-models' volume (podman/docker volume rm zsh-localghost-models to delete them)."
  exit 0
fi

# 1. requirements (warn, do not abort: the plugin explains what is missing when it runs)
for c in git curl python3; do have "$c" || { say "missing: $c (required)"; exit 1; }; done
have zsh || { say "missing: zsh (required)"; exit 1; }
ver=$(zsh --version | awk '{print $2}'); major=${ver%%.*}; rest=${ver#*.}; minor=${rest%%.*}
{ [ "$major" -gt 5 ] || { [ "$major" -eq 5 ] && [ "$minor" -ge 9 ]; }; } || say "warning: zsh $ver found, 5.9 or newer is needed (the colours use region_highlight memo=)"
if have podman; then ENGINE=podman; elif have docker; then ENGINE=docker; else
  say "warning: neither podman nor docker found. The plugin installs, but it needs one of them (or your own server: export ZLG_URL=http://host:port/infill) to answer."
fi

# 2. fetch or update the plugin
if [ -d "$DIR/.git" ]; then
  say "updating $DIR"; git -C "$DIR" pull --ff-only -q
else
  say "installing into $DIR"; mkdir -p "$(dirname "$DIR")"; git clone --depth 1 -q "$REPO" "$DIR"
fi

# 3. one marked block at the END of .zshrc (it must come after zsh-autosuggestions, which resets a list this plugin extends)
if [ -f "$RC" ] && grep -qF "$BEGIN" "$RC"; then
  say "$RC already has the block, left as is"
else
  [ -f "$RC" ] && [ -s "$RC" ] && [ "$(tail -c1 "$RC" | wc -l)" -eq 0 ] && printf '\n' >> "$RC"
  { printf '\n%s\n' "$BEGIN"; printf 'source "%s/zsh-localghost.plugin.zsh"\n' "$DIR"; printf '%s\n' "$END"; } >> "$RC"
  say "added the block to the end of $RC"
fi
if [ -f "$RC" ] && grep -q "autosuggestions" "$RC" && ! awk -v b="$BEGIN" '/autosuggestions/{a=NR} $0==b{p=NR} END{exit !(p>a)}' "$RC"; then
  say "note: zsh-autosuggestions is loaded after this block in $RC. Move the zsh-localghost block below it."
fi

[ "$1" = "--pull" ] && [ -n "${ENGINE:-}" ] && { say "pulling the model server image..."; "$DIR/bin/zlg" pull; }

say ""
say "installed. Open a new terminal (or run: exec zsh), type something like  git log --  and press Ctrl+Space."
say "The first time it starts the local model server by itself (downloads ~860 MB image + ~2 GB models); try again after a minute."
