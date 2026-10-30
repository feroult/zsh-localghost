# Usage: zsh test/destructive_test.zsh test/destructive_cases.txt
# Loads only the classifier from the plugin and checks it against destructive_cases.txt (expected<TAB>command).
# Runs a pure string match: nothing here executes the listed commands.
zle() { : }; bindkey() { :; }; add-zle-hook-widget() { :; }
source "${0:A:h}/../zsh-localghost.plugin.zsh" 2>/dev/null
fails=0
while IFS=$'\t' read -r want cmd; do
  if _zlg_is_destructive "$cmd"; then got=FLAG; else got=ok; fi
  [[ $got == $want ]] && mark="  " || { mark="!!"; (( fails++ )); }
  printf '%s %-5s (want %-4s) %s\n' "$mark" "$got" "$want" "$cmd"
done < "${1:?cases file}"
echo "mismatches: $fails"
