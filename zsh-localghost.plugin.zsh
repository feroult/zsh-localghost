# zsh-localghost: shell suggestions from a local llama-server (Qwen2.5-Coder, FIM) running in a container.
# Source from ~/.zshrc AFTER zsh-autosuggestions. The container is pulled and started on first use (see bin/zlg).
#   Ctrl+Space  looks at the buffer: part of a command -> completes it (ghost text);
#               plain text (a request in English/Portuguese) -> generates the command (shown as "-> command")
#   Ctrl+F      accepts (completion: appends; request: replaces the buffer with the command)
#   Enter       with a suggestion on screen: accepts it and runs it, unless it is flagged destructive
#               (then it only goes into the buffer and a second Enter runs it). Without a suggestion Enter is untouched.
#   Ctrl+X Ctrl+R  forces "request" mode when the guess was wrong
# Settings (export before sourcing):
#   ZLG_URL                  main model (1.5B): used for completing and for writing commands
#   ZLG_URL_FAST             optional faster model (0.5B, http://localhost:8766/infill) for completion only; measured
#                            ~2x faster but clearly less accurate, so it is off by default
#   ZLG_AUTOSTART=0          do not start the container automatically (default: start it on the first request)
#   ZLG_ENTER=0              do not touch Enter
#   ZLG_KEY                  extra key sequence that triggers a suggestion, e.g. ZLG_KEY=$'\e[13;5u' (find yours: run `cat -v`, press the key)
#   ZLG_STYLE_COMPLETE, ZLG_STYLE_COMMAND, ZLG_STYLE_ARROW, ZLG_STYLE_WARN   region_highlight styles
#   ZLG_ARROW, ZLG_WARN_MARK   the glyphs shown before a generated command / on a destructive one
: ${ZLG_PORT:=8765}
: ${ZLG_PORT_FAST:=8766}
: ${ZLG_URL:=http://localhost:$ZLG_PORT/infill}
export ZLG_PORT ZLG_PORT_FAST
: ${ZLG_N_PREDICT:=40}
# Pastel defaults (256-colour palette numbers). For exact colours use e.g. fg=#9ad1d4 (needs a truecolor terminal,
# or `zmodload zsh/nearcolor`). If the terminal advertises fewer than 256 colours (TERM=xterm gives 8, so fg=116 would paint
# nothing), fall back to the basic ones.
zmodload zsh/terminfo 2>/dev/null
if (( ${terminfo[colors]:-8} >= 256 )); then
  : ${ZLG_STYLE_COMPLETE:=fg=245}     # medium-dark grey
  : ${ZLG_STYLE_COMMAND:=fg=245}      # medium-dark grey
  : ${ZLG_STYLE_ARROW:=fg=103}        # muted lavender
  : ${ZLG_STYLE_WARN:=fg=217,bold}    # soft coral
else
  : ${ZLG_STYLE_COMPLETE:=fg=8}
  : ${ZLG_STYLE_COMMAND:=fg=8}
  : ${ZLG_STYLE_ARROW:=fg=blue}
  : ${ZLG_STYLE_WARN:=fg=red,bold}
fi
# Glyphs: standard Unicode symbols when the locale is UTF-8 (they exist in every font), plain ASCII otherwise.
# Override with e.g. ZLG_ARROW='❯ ' or a Nerd Font icon $'\uf061 '. The default has one space before the arrow; use ZLG_ARROW='→ ' for none.
_zlg_loc="${LC_ALL:-${LC_CTYPE:-$LANG}}"
if [[ "$_zlg_loc" == *[Uu][Tt][Ff]-8* || "$_zlg_loc" == *[Uu][Tt][Ff]8* ]]; then
  : ${ZLG_ARROW:=' → '}
  : ${ZLG_WARN_MARK:='⚠ destructive?'}
else
  : ${ZLG_ARROW:=' -> '}
  : ${ZLG_WARN_MARK:='[!] destructive?'}
fi
_ZLG_DIR="${0:A:h}"
_ZLG_HELPER="$_ZLG_DIR/lib/query.py"
typeset -g _ZLG_SUGGESTION="" _ZLG_REPLACE=0 _ZLG_WARN=0 _ZLG_BUF=""
# Our highlights are tagged memo=zsh-localghost and removed by that tag: zsh shifts the offsets of existing highlights
# when the line is edited (e.g. Ctrl+U), so removing them by their exact text does not work. Needs zsh >= 5.9.
_zlg_clear_ghost() {
  POSTDISPLAY=""; _ZLG_SUGGESTION=""
  region_highlight=("${(@)region_highlight:#*memo=zsh-localghost}")
}
_zlg_hl() { region_highlight+=("$1 $2 $3,memo=zsh-localghost"); }   # start end style

# Commands that lose data or are hard to undo: when a suggestion contains one, Enter only puts it in the buffer
# (a second Enter runs it). Each pattern must start at a word boundary (start of line, or after space | ; & ( )
# so that a word such as "terraform" does not match the pattern for rm.
typeset -ga _ZLG_DESTRUCTIVE=(
  'rm *' 'rmdir *' 'unlink *' 'shred *' 'truncate *' 'dd *' 'mkfs*' ':(){*' 'sudo *'
  'chmod -R*' 'chown -R*' '* -delete*' '*> /dev/*' '*>/dev/*'
  'git reset --hard*' 'git clean *' 'git checkout -- *' 'git checkout .*' 'git restore *' 'git stash drop*' 'git stash clear*'
  'git branch -D*' 'git push *--force*' 'git push * -f*' 'git push -f*'
  'docker rm*' 'docker rmi*' 'docker system prune*' 'docker volume rm*' 'docker volume prune*' 'docker container prune*' 'docker image prune*'
  'kubectl delete*' 'terraform destroy*' '*DROP TABLE*' '*DROP DATABASE*' '*drop table*' '*drop database*'
)
_zlg_is_destructive() {
  local s="$1" p
  for p in "${_ZLG_DESTRUCTIVE[@]}"; do
    [[ "$s" == ${~:-"(|*[ |;&(])"}${~p} ]] && return 0
  done
  return 1
}

# Is the buffer a request in words (1) or part of a command (0)?
_zlg_looks_like_request() {
  local buf="$BUFFER"
  [[ -z "${buf// /}" ]] && return 1
  [[ "$buf" == *[^[:ascii:]]* ]] && return 0                      # accented text: Portuguese prose
  local -a w; w=(${(z)buf})
  local first="${w[1]}"
  [[ "$first" == *=* || "$first" == [./~]* ]] && return 1          # VAR=x cmd, ./script, /bin/x, ~/x
  if ! whence -w -- "$first" >/dev/null 2>&1; then
    (( $#w == 1 )) && [[ "$buf" != *" " ]] && return 1             # a single unknown word: a command being typed
    [[ "$buf" == *[-/.=\|\>\<\$~\*\'\"\;\&\(\)]* ]] && return 1    # flags/paths/quotes: a command that is not installed here
    return 0                                                       # unknown first word + more words: prose
  fi
  # known command followed by 3+ plain words with no flags/paths/quotes (e.g. "find which process is using port 80")
  (( $#w >= 4 )) && [[ "${buf}" != *[-/.=\|\>\<\$~\*\'\"\;\&\(\)]* ]] && return 0
  return 1
}

# Transparent start: if nothing answers, start the container in the background (first run pulls the image and the models).
_zlg_ensure_server() {
  curl -sf -m 0.5 "${ZLG_URL%/infill}/health" >/dev/null 2>&1 && return 0
  (( ${ZLG_AUTOSTART:-1} )) || { zle -M "zsh-localghost: no server at $ZLG_URL"; return 1 }
  zle -M "zsh-localghost: starting the local model server (first run downloads ~2 GB) - try again in a moment"
  ( "$_ZLG_DIR/bin/zlg" start >/dev/null 2>&1 & )
  return 1
}
_zlg_run() {   # $1 = auto | request
  _zlg_ensure_server || return
  local request=0 url="$ZLG_URL"
  if [[ "$1" == request ]] || { [[ "$1" == auto ]] && _zlg_looks_like_request; }; then request=1
  elif [[ -n "$ZLG_URL_FAST" ]]; then url="$ZLG_URL_FAST"; fi
  local out
  out=$(fc -ln -8 2>/dev/null | sed 's/^ *//' | ZLG_MODE=$( (( request )) && print request || print complete ) python3 "$_ZLG_HELPER" "$url" "$BUFFER" "$ZLG_N_PREDICT" 2>/dev/null)
  _zlg_clear_ghost
  _ZLG_SUGGESTION="$out" _ZLG_BUF="$BUFFER" _ZLG_WARN=0 _ZLG_REPLACE=$request
  [[ -z "$out" ]] && { zle -R; return }
  local arrow="" warn=""
  (( request )) && arrow="$ZLG_ARROW"
  _zlg_is_destructive "$out" && { warn=" $ZLG_WARN_MARK"; _ZLG_WARN=1; }
  POSTDISPLAY="${arrow}${out}${warn}"
  local b=$#BUFFER style="$ZLG_STYLE_COMPLETE"
  (( request )) && { _zlg_hl $b $(( b + $#arrow )) "$ZLG_STYLE_ARROW"; style="$ZLG_STYLE_COMMAND" }
  _zlg_hl $(( b + $#arrow )) $(( b + $#arrow + $#out )) "$style"
  [[ -n "$warn" ]] && _zlg_hl $(( b + $#arrow + $#out )) $(( b + $#POSTDISPLAY )) "$ZLG_STYLE_WARN"
  zle -R
}
_zlg_suggest() { _zlg_run auto }
_zlg_ask() { _zlg_run request }
_zlg_accept() {
  if [[ -n "$_ZLG_SUGGESTION" ]]; then
    if (( _ZLG_REPLACE )); then BUFFER="$_ZLG_SUGGESTION"; else BUFFER+="$_ZLG_SUGGESTION"; fi
    CURSOR=${#BUFFER}; _zlg_clear_ghost
  else zle forward-char; fi
}
# Enter with a suggestion on screen: accept it (completion appends, request replaces the buffer) and run it.
# Chains to whatever accept-line was defined before (other plugins) instead of replacing it.
_zlg_enter() {
  if [[ -n "$_ZLG_SUGGESTION" ]]; then
    local warned=$_ZLG_WARN
    _zlg_accept
    (( warned )) || zle _zlg_orig_accept_line
  else _zlg_clear_ghost; zle _zlg_orig_accept_line; fi
}
# Runs before every redraw: drop the ghost text once the buffer changed (a hook, so no widget such as self-insert is replaced).
_zlg_line_changed() { [[ -n "$_ZLG_SUGGESTION" && "$BUFFER" != "$_ZLG_BUF" ]] && _zlg_clear_ghost }
autoload -Uz add-zle-hook-widget
zle -N _zlg_suggest; zle -N _zlg_ask; zle -N _zlg_accept; zle -N _zlg_line_changed
add-zle-hook-widget line-pre-redraw _zlg_line_changed
# zsh-autosuggestions wraps every widget and would overwrite our ghost text: tell it to leave ours alone.
# (Source this file AFTER zsh-autosuggestions, which resets this array when it loads.)
ZSH_AUTOSUGGEST_IGNORE_WIDGETS+=(_zlg_suggest _zlg_ask _zlg_accept)
if (( ${ZLG_ENTER:-1} )) && [[ ${widgets[accept-line]} != user:_zlg_enter ]]; then
  zle -A accept-line _zlg_orig_accept_line
  zle -N _zlg_enter
  zle -A _zlg_enter accept-line
fi
bindkey '^@' _zlg_suggest      # Ctrl+Space (if your terminal swallows it: ZLG_KEY=$'\x18\x06' for Ctrl+X Ctrl+F)
[[ -n "$ZLG_KEY" ]] && bindkey "$ZLG_KEY" _zlg_suggest
bindkey '^X^R' _zlg_ask
bindkey '^F' _zlg_accept
