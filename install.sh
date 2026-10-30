#!/bin/sh
# zsh-localghost installer.  Usage:
#   curl -fsSL https://raw.githubusercontent.com/feroult/zsh-localghost/main/install.sh | sh
#   sh install.sh --uninstall        remove the block from your .zshrc and the install directory
#   sh install.sh --no-wait          start the model server but do not wait for the models to finish downloading
#   sh install.sh --no-start         do not start the model server now (it then starts on the first Ctrl+Space, and that first press only starts it)
#   (through a pipe: curl ... | sh -s -- --no-wait)
# Environment: ZLG_HOME (install dir, default ~/.zsh/zsh-localghost), ZLG_REPO (git url to clone), ZDOTDIR (where .zshrc lives).
# It only touches ZLG_HOME and one marked block at the end of your .zshrc. No sudo, no system changes.
set -e

REPO="${ZLG_REPO:-https://github.com/feroult/zsh-localghost}"
DIR="${ZLG_HOME:-$HOME/.zsh/zsh-localghost}"
RC="${ZDOTDIR:-$HOME}/.zshrc"
BEGIN="# >>> zsh-localghost >>>"
END="# <<< zsh-localghost <<<"

NOSTART=0; NOWAIT=0; UNINSTALL=0
for a in "$@"; do case "$a" in --no-start) NOSTART=1;; --no-wait) NOWAIT=1;; --uninstall) UNINSTALL=1;; esac; done

say() { printf '%s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

backup_rc() {   # a dated copy next to the file, made right before this script changes it; aborts if it cannot be made
  [ -s "$RC" ] || return 0
  bak="$RC.zlg-bak-$(date +%Y%m%d-%H%M%S)"
  cp "$RC" "$bak" || { say "could not write a backup of $RC, leaving it untouched"; exit 1; }
  say "backup of your .zshrc: $bak"
}

remove_block() {
  [ -f "$RC" ] && grep -qF "$BEGIN" "$RC" || return 0
  backup_rc
  tmp="$RC.zlg.$$"
  # drops the block and the blank line this installer put in front of it
  awk -v b="$BEGIN" -v e="$END" '{l[NR]=$0}
    END{for(i=1;i<=NR;i++) if(l[i]==b){s=i;break}
        for(i=s;i<=NR;i++) if(l[i]==e){t=i;break}
        if(s>1 && l[s-1]=="") s--
        for(i=1;i<=NR;i++) if(i<s||i>t) print l[i]}' "$RC" > "$tmp" && cat "$tmp" > "$RC" && rm -f "$tmp"
  say "removed the zsh-localghost block from $RC"
}

if [ "$UNINSTALL" = 1 ]; then
  remove_block
  # only delete a directory that really is an install of this project
  if [ -f "$DIR/lib/query.py" ] && [ -f "$DIR/zsh-localghost.plugin.zsh" ]; then
    rm -rf -- "$DIR" && say "removed $DIR"
  fi
  C="${ZLG_CONTAINER:-zsh-localghost}"; V="${ZLG_VOLUME:-zsh-localghost-models}"
  have podman && podman rm -f "$C" >/dev/null 2>&1 || true
  have docker && docker rm -f "$C" >/dev/null 2>&1 || true
  say "done. The downloaded models stay in the '$V' volume (podman/docker volume rm $V to delete them)."
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
  backup_rc
  [ -f "$RC" ] && [ -s "$RC" ] && [ "$(tail -c1 "$RC" | wc -l)" -eq 0 ] && printf '\n' >> "$RC"
  { printf '\n%s\n' "$BEGIN"; printf 'source "%s/zsh-localghost.plugin.zsh"\n' "$DIR"; printf '%s\n' "$END"; } >> "$RC"
  say "added the block to the end of $RC"
fi
if [ -f "$RC" ] && grep -q "autosuggestions" "$RC" && ! awk -v b="$BEGIN" '/autosuggestions/{a=NR} $0==b{p=NR} END{exit !(p>a)}' "$RC"; then
  say "note: zsh-autosuggestions is loaded after this block in $RC. Move the zsh-localghost block below it."
fi

# 4. start the model server now and wait for it (progress bar), so that the first Ctrl+Space already answers.
#    `zlg start` pulls the image (~860 MB, the engine shows its own progress); the container then downloads ~2 GB of models.
STARTED=0; READY=0
if [ "$NOSTART" = 0 ] && [ -n "${ENGINE:-}" ]; then
  say "starting the model server (pulls the ~860 MB image, then the models, ~2 GB, download inside the container)..."
  if "$DIR/bin/zlg" start; then
    STARTED=1
    if [ "$NOWAIT" = 0 ]; then "$DIR/bin/zlg" wait 900 && READY=1 || say "it is taking longer than expected; it keeps going in the background (zlg logs)"; fi
  else
    say "could not start it now; it will be started on your first Ctrl+Space"
  fi
fi

say ""
say "installed. Open a new terminal (or run: exec zsh), type something like  git log --  and press Ctrl+Space."
if [ "$READY" = 1 ]; then
  say "The model server is ready."
elif [ "$STARTED" = 1 ]; then
  say "The model server is still warming up: if you get no suggestion yet, wait a little and press Ctrl+Space again (progress: $DIR/bin/zlg wait)."
else
  say "The first Ctrl+Space starts the model server (downloads ~860 MB image + ~2 GB models); try again after a minute."
fi
