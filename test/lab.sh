#!/bin/sh
# Throwaway Ubuntu container with zsh + zsh-autosuggestions + this plugin, to try it without touching your own ~/.zshrc.
#   test/lab.sh            create (or recreate) the lab and print how to enter it
# Needs the inference container reachable at host.containers.internal; override with ZLG_URL / ZLG_URL_FAST when running this script.
ENGINE="${ZLG_ENGINE:-$(command -v podman || command -v docker)}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
$ENGINE rm -f zlg-lab >/dev/null 2>&1
$ENGINE run -d --name zlg-lab docker.io/library/ubuntu:24.04 sleep infinity >/dev/null || exit 1
$ENGINE exec zlg-lab sh -c 'apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq zsh curl python3 git >/dev/null 2>&1 &&
  git clone -q --depth 1 https://github.com/zsh-users/zsh-autosuggestions /root/.zsh-autosuggestions && mkdir -p /plugin' || exit 1
$ENGINE cp "$HERE/." zlg-lab:/plugin
cat <<EOT | $ENGINE exec -i zlg-lab sh -c 'cat > /root/.zshrc'
export LANG=C.UTF-8 TERM=xterm-256color
source /root/.zsh-autosuggestions/zsh-autosuggestions.zsh
export ZLG_AUTOSTART=0
export ZLG_URL=${ZLG_URL:-http://host.containers.internal:31865/infill}
source /plugin/zsh-localghost.plugin.zsh
PS1="%~ %# "
cd ~
EOT
echo "lab ready: $ENGINE exec -it zlg-lab zsh"
