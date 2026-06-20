#!/usr/bin/env bash
# hacker-dash: Bash/tmux-friendly TARGET/HUNTER dashboard.
# Source it to update the current shell variables:
#   source ~/bin/hacker-dash

set +e

APP_NAME="hacker-dash"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hacker-dash"
STATE_FILE="$CONFIG_DIR/state.env"
LEGACY_JSON="$CONFIG_DIR/state.json"

TARGET="${TARGET:-}"
HUNTER="${HUNTER:-}"
HD_SELECTED=0
HD_STATUS=""

is_sourced() {
  [[ "${BASH_SOURCE[0]}" != "$0" ]]
}

finish() {
  local code="${1:-0}"
  if is_sourced; then
    return "$code"
  fi
  exit "$code"
}

quote_shell() {
  printf '%q' "$1"
}

load_state() {
  mkdir -p "$CONFIG_DIR"

  if [[ -f "$STATE_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$STATE_FILE"
    return
  fi

  if [[ -f "$LEGACY_JSON" ]]; then
    local old_target old_hunter
    old_target="$(awk -F'\"' '/"target_ip"/ {print $4; exit}' "$LEGACY_JSON" 2>/dev/null)"
    old_hunter="$(awk -F'\"' '/"hunter_ip"/ {print $4; exit}' "$LEGACY_JSON" 2>/dev/null)"
    [[ -n "$old_target" ]] && TARGET="$old_target"
    [[ -n "$old_hunter" ]] && HUNTER="$old_hunter"
    save_state
  fi
}

save_state() {
  mkdir -p "$CONFIG_DIR"
  {
    printf 'export TARGET=%s\\n' "$(quote_shell "$TARGET")"
    printf 'export HUNTER=%s\\n' "$(quote_shell "$HUNTER")"
  } > "$STATE_FILE"
  chmod 600 "$STATE_FILE" 2>/dev/null
}

export_vars() {
  export TARGET
  export HUNTER

  if [[ -n "${TMUX:-}" ]] && command -v tmux >/dev/null 2>&1; then
    tmux set-environment -g TARGET "$TARGET" 2>/dev/null
    tmux set-environment -g HUNTER "$HUNTER" 2>/dev/null
  fi
}

notify_parent_shell() {
  if [[ "${HACKER_DASH_NOTIFY_PID:-}" =~ ^[0-9]+$ ]]; then
    kill -USR1 "${HACKER_DASH_NOTIFY_PID}" 2>/dev/null || true
  fi
}

selected_name() {
  if [[ "$HD_SELECTED" -eq 0 ]]; then
    printf 'TARGET'
  else
    printf 'HUNTER'
  fi
}

selected_value() {
  if [[ "$HD_SELECTED" -eq 0 ]]; then
    printf '%s' "$TARGET"
  else
    printf '%s' "$HUNTER"
  fi
}

set_selected_value() {
  if [[ "$HD_SELECTED" -eq 0 ]]; then
    TARGET="$1"
  else
    HUNTER="$1"
  fi
  save_state
  export_vars
  notify_parent_shell
}

osc52_copy() {
  local text="$1" encoded
  command -v base64 >/dev/null 2>&1 || return 1
  encoded="$(printf '%s' "$text" | base64 | tr -d '\\n')"

  if [[ -n "${TMUX:-}" ]]; then
    printf '\\033Ptmux;\\033\\033]52;c;%s\\a\\033\\\\' "$encoded"
  else
    printf '\\033]52;c;%s\\a' "$encoded"
  fi
}

copy_clipboard() {
  local text="$1"

  if [[ -n "${TMUX:-}" ]] && command -v tmux >/dev/null 2>&1; then
    if tmux set-buffer -w -- "$text" 2>/dev/null; then
      return 0
    fi
    tmux set-buffer -- "$text" 2>/dev/null || true
  fi

  if [[ -n "${WAYLAND_DISPLAY:-}" ]] && command -v wl-copy >/dev/null 2>&1; then
    printf '%s' "$text" | wl-copy && return 0
  fi

  if [[ -n "${DISPLAY:-}" ]] && command -v xclip >/dev/null 2>&1; then
    printf '%s' "$text" | xclip -selection clipboard && return 0
  fi

  if [[ -n "${DISPLAY:-}" ]] && command -v xsel >/dev/null 2>&1; then
    printf '%s' "$text" | xsel --clipboard --input && return 0
  fi

  if command -v pbcopy >/dev/null 2>&1; then
    printf '%s' "$text" | pbcopy && return 0
  fi

  osc52_copy "$text"
}

clear_screen() {
  printf '\\033[2J\\033[H'
}

# --- Minimal Modern Palette ---
bold='\033[1m'
grey='\033[38;5;244m'
white='\033[0m'
underline='\033[4m'
reset='\033[0m'

row() {
  local idx="$1" name="$2" value="$3"
  if [[ "$HD_SELECTED" -eq "$idx" ]]; then
    printf '  %b%s %s%b\n' "$white" "$name" "$value" "$reset"
    # Subtle underline effect for selected row in bash
    printf '  %b%s%b\n' "$grey" "────────────────────────────" "$reset"
  else
    printf '  %b%s %b%s%b\n' "$grey" "$name" "$white" "$value" "$reset"
  fi
}

draw_dashboard() {
  clear_screen
  printf '%b──────────────────────────────%b\n' "$grey" "$reset"
  printf '  %bHACKER DASHBOARD%b\n' "$bold" "$reset"
  printf '%b──────────────────────────────%b\n' "$grey" "$reset"
  row 0 'TARGET:' "$TARGET"
  printf '\n'
  row 1 'HUNTER:' "$HUNTER"
  printf '%b──────────────────────────────%b\n' "$grey" "$reset"
  printf '  %b↑/↓ j/k select   ENTER action%b\n' "$grey" "$reset"
  printf '  %bq quit             %be edit%b\n' "$grey" "$reset" "$grey" "$reset"
  if [[ -n "$HD_STATUS" ]]; then
    printf '\n  %b%s%b\n' "$grey" "$HD_STATUS" "$reset"
  fi
}

read_key() {
  local key rest
  IFS= read -rsn1 key
  if [[ "$key" == $'\x1b' ]]; then
    IFS= read -rsn2 -t 0.05 rest
    key+="$rest"
  fi
  printf '%s' "$key"
}

action_menu() {
  local action=0 key name value
  name="$(selected_name)"
  value="$(selected_value)"

  while true; do
    clear_screen
    printf '%b──────────────────────────────%b\n' "$grey" "$reset"
    printf '  %bAction for %-6s%b\n' "$bold" "$name" "$reset"
    printf '%b──────────────────────────────%b\n' "$grey" "$reset"
    printf '  %b%s%b\n\n' "$grey" "$value" "$reset"

    if [[ "$action" -eq 0 ]]; then printf '  %b Copy to clipboard %b\n' "$white" "$reset"; else printf '   Copy to clipboard\n'; fi
    if [[ "$action" -eq 1 ]]; then printf '  %b Change IP         %b\n' "$white" "$reset"; else printf '   Change IP\n'; fi
    if [[ "$action" -eq 2 ]]; then printf '  %b Back              %b\n' "$white" "$reset"; else printf '   Back\n'; fi

    printf '\n  %b↑/↓ select, ENTER confirm%b\n' "$grey" "$reset"
    printf '%b──────────────────────────────%b\n' "$grey" "$reset"

    key="$(read_key)"
    case "$key" in
      $'\x1b[A'|k|K) (( action > 0 )) && ((action--)) ;;\n      $'\x1b[B'|j|J) (( action < 2 )) && ((action++)) ;;\n      q|Q|b|B) return ;;\n      '')\n        case "$action" in\n          0) copy_selected; return ;;\n          1) edit_selected; return ;;\n          2) return ;;\n        esac\n        ;;\n    esac\n  done\n}

copy_selected() {
  local name value
  name="$(selected_name)"
  value="$(selected_value)"

  export_vars
  save_state

  if [[ -z "$value" ]]; then
    HD_STATUS="$name is empty; nothing copied."
    return
  fi

  if copy_clipboard "$value"; then
    HD_STATUS="Copied $name to clipboard"
  else
    HD_STATUS="Exported $$name, but clipboard failed"
  fi
  notify_parent_shell
}

edit_selected() {
  local name current new_value
  name="$(selected_name)"
  current="$(selected_value)"

  clear_screen
  printf '%bChange %s%b\n\n' "$bold" "$name" "$reset"
  printf 'Current: %s\n' "$current"
  printf 'New IP: '
  IFS= read -r new_value

  set_selected_value "$new_value"
  HD_STATUS="Updated $name"
}

run_ui() {
  load_state
  export_vars

  while true; do
    draw_dashboard
    local key
    key="$(read_key)"
    case "$key" in
      $'\x1b[A'|k|K) HD_SELECTED=0 ;;\n      $'\x1b[B'|j|J) HD_SELECTED=1 ;;\n      e|E) edit_selected ;;\n      q|Q|$'\x03') clear_screen; return 0 ;;\n      '') action_menu ;;\n    esac
  done
}

print_env() {
  load_state
  printf 'export TARGET=%s\\n' "$(quote_shell "$TARGET")"
  printf 'export HUNTER=%s\\n' "$(quote_shell "$HUNTER")"
}

usage() {
  cat <<'USAGE'
hacker-dash bash version

Usage:
  source ~/bin/hacker-dash        # interactive UI; updates current shell TARGET/HUNTER
  ~/bin/hacker-dash               # interactive UI; cannot update parent shell, but updates state/tmux env
  ~/bin/hacker-dash --print-env   # print export commands
  source ~/bin/hacker-dash --set TARGET 10.10.10.10
  source ~/bin/hacker-dash --set HUNTER 10.10.14.2

Keys:
  up/down or k/j  select TARGET/HUNTER
  ENTER           choose Copy / Change / Back
  e               edit selected IP
  q               quit
USAGE
}

main() {
  case "${1:-}" in
    --help|-h)
      usage
      return 0
      ;;\n    --print-env)
      print_env
      return 0
      ;;\n    --set)
      load_state
      case "${2:-}" in
        TARGET) TARGET="${3:-}" ;;\n        HUNTER) HUNTER="${3:-}" ;;\n        *) printf 'Usage: --set TARGET|HUNTER value\\n' >&2; return 2 ;;\n      esac
      save_state
      export_vars
      notify_parent_shell
      return 0
      ;;\n    --clear)
      TARGET=""
      HUNTER=""
      save_state
      export_vars
      notify_parent_shell
      return 0
      ;;\n    *)\n      run_ui
      ;;\n  esac
}

main "$@"
finish $?
