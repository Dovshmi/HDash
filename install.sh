#!/usr/bin/env bash
# Install hacker-dash and a Ctrl-g tmux popup binding.

set -euo pipefail

APP_NAME="hacker-dash"
SRC_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SRC="$SRC_DIR/hacker-dash.sh"
BIN_DIR="$HOME/bin"
DEST="$BIN_DIR/hacker-dash"
TMUX_CONF="$HOME/.tmux.conf"
BLOCK_START="# BEGIN hacker-dash tmux"
BLOCK_END="# END hacker-dash tmux"

quote_shell() {
  printf '%q' "$1"
}

install_script() {
  if [[ ! -f "$SRC" ]]; then
    printf 'Error: %s not found\n' "$SRC" >&2
    exit 1
  fi

  mkdir -p "$BIN_DIR"

  # Atomic replace avoids "Text file busy" if the old script is running.
  local tmp
  tmp="$DEST.new"
  install -m 755 "$SRC" "$tmp"
  mv -f "$tmp" "$DEST"
}

install_tmux_binding() {
  local dest_q binding tmp
  dest_q="$(quote_shell "$DEST")"
  binding="bind-key -n C-g display-popup -E -w 46 -h 12 -x R -y C -T \" hacker-dash \" \"HACKER_DASH_IN_POPUP=1 HACKER_DASH_NOTIFY_PID=#{pane_pid} bash $dest_q --no-popup\""

  touch "$TMUX_CONF"
  tmp="$(mktemp)"

  awk -v start="$BLOCK_START" -v end="$BLOCK_END" '
    $0 == start { in_block = 1; next }
    $0 == end { in_block = 0; next }
    in_block { next }
    /hacker-dash/ && /display-popup/ { next }
    { print }
  ' "$TMUX_CONF" > "$tmp"

  {
    cat "$tmp"
    printf '\n%s\n' "$BLOCK_START"
    printf '# Ctrl-g opens Hacker Dash in a tmux popup.\n'
    printf '# --no-popup prevents recursive popups; pane_pid lets the popup notify this shell.\n'
    printf '%s\n' "$binding"
    printf '%s\n' "$BLOCK_END"
  } > "$TMUX_CONF"

  rm -f "$tmp"

  if [[ -n "${TMUX:-}" ]] && command -v tmux >/dev/null 2>&1; then
    tmux source-file "$TMUX_CONF"
  fi
}

main() {
  install_script
  install_tmux_binding

  printf 'Installed %s\n' "$DEST"
  printf 'Installed tmux Ctrl-g binding in %s\n' "$TMUX_CONF"
  if [[ -n "${TMUX:-}" ]]; then
    printf 'Reloaded tmux config. Press Ctrl-g to open Hacker Dash.\n'
  else
    printf 'Start/reload tmux, then press Ctrl-g to open Hacker Dash.\n'
  fi
}

main "$@"
