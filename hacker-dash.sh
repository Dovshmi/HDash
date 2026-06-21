#!/usr/bin/env bash
# hacker-dash: minimal TARGET/HUNTER dashboard for shells and tmux.
# Source it when you want the current shell to receive updated variables:
#   source ./hacker-dash.sh

# If this file is sourced from zsh, do not run the Bash TUI code in zsh.
# Run the UI with bash, then import the saved TARGET/HUNTER into zsh.
if [ -z "${BASH_VERSION:-}" ]; then
  if [ -n "${ZSH_VERSION:-}" ]; then
    _hd_self="${(%):-%x}"
  else
    _hd_self="$0"
  fi

  case "$_hd_self" in
    /*) ;;
    */*)
      _hd_dir="$(dirname -- "$_hd_self")"
      _hd_base="$(basename -- "$_hd_self")"
      _hd_self="$(cd -- "$_hd_dir" 2>/dev/null && pwd)/$_hd_base"
      ;;
    *) _hd_self="$(command -v -- "$_hd_self" 2>/dev/null)" ;;
  esac

  if [ -z "$_hd_self" ]; then
    printf 'hacker-dash: could not find script path\n' >&2
    return 1 2>/dev/null || exit 1
  fi

  case "${1:-}" in
    --print-env|--help|-h|--set|--clear)
      bash "$_hd_self" "$@"
      _hd_rc=$?
      ;;
    *)
      if [ -n "${TMUX:-}" ] && [ -z "${HACKER_DASH_IN_POPUP:-}" ] && [ "${1:-}" != "--no-popup" ] && command -v tmux >/dev/null 2>&1; then
        _hd_q="$(printf '%q' "$_hd_self")"
        tmux display-popup -E -w 46 -h 12 -T " hacker-dash " "HACKER_DASH_IN_POPUP=1 bash $_hd_q --no-popup"
        _hd_rc=$?
      else
        bash "$_hd_self" "$@"
        _hd_rc=$?
      fi
      ;;
  esac

  eval "$(bash "$_hd_self" --print-env)"
  unset _hd_self _hd_q
  return "$_hd_rc" 2>/dev/null || exit "$_hd_rc"
fi

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

script_path() {
  local src="${BASH_SOURCE[0]}"
  if [[ "$src" == */* ]]; then
    (cd -- "$(dirname -- "$src")" 2>/dev/null && printf '%s/%s\n' "$PWD" "$(basename -- "$src")")
  else
    command -v -- "$src"
  fi
}

migrate_legacy_json() {
  [[ -f "$LEGACY_JSON" ]] || return 0
  [[ -f "$STATE_FILE" ]] && return 0

  local old_target old_hunter
  old_target="$(awk -F'"' '/"target_ip"/ {print $4; exit}' "$LEGACY_JSON" 2>/dev/null)"
  old_hunter="$(awk -F'"' '/"hunter_ip"/ {print $4; exit}' "$LEGACY_JSON" 2>/dev/null)"

  [[ -n "$old_target" ]] && TARGET="$old_target"
  [[ -n "$old_hunter" ]] && HUNTER="$old_hunter"
  save_state
}

load_state() {
  mkdir -p "$CONFIG_DIR"
  migrate_legacy_json

  if [[ -f "$STATE_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$STATE_FILE"
  fi
}

save_state() {
  mkdir -p "$CONFIG_DIR"
  {
    printf 'export TARGET=%s\n' "$(quote_shell "$TARGET")"
    printf 'export HUNTER=%s\n' "$(quote_shell "$HUNTER")"
  } > "$STATE_FILE"
  chmod 600 "$STATE_FILE" 2>/dev/null || true
}

export_vars() {
  export TARGET
  export HUNTER

  if [[ -n "${TMUX:-}" ]] && command -v tmux >/dev/null 2>&1; then
    tmux set-environment -g TARGET "$TARGET" 2>/dev/null || true
    tmux set-environment -g HUNTER "$HUNTER" 2>/dev/null || true
  fi
}

refresh_env_from_state() {
  load_state
  export_vars
}

notify_parent_shell() {
  if [[ "${HACKER_DASH_NOTIFY_PID:-}" =~ ^[0-9]+$ ]]; then
    kill -USR1 "$HACKER_DASH_NOTIFY_PID" 2>/dev/null || true
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
  encoded="$(printf '%s' "$text" | base64 | tr -d '\n')"

  if [[ -n "${TMUX:-}" ]]; then
    printf '\033Ptmux;\033\033]52;c;%s\a\033\\' "$encoded"
  else
    printf '\033]52;c;%s\a' "$encoded"
  fi
}

copy_clipboard() {
  local text="$1"
  [[ -z "$text" ]] && return 1

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

  if [[ -n "${TMUX:-}" ]] && command -v tmux >/dev/null 2>&1; then
    tmux set-buffer -w -- "$text" 2>/dev/null && return 0
    tmux set-buffer -- "$text" 2>/dev/null && return 0
  fi

  osc52_copy "$text"
}

clear_screen() {
  printf '\033[2J\033[H'
}

# Minimal, modern grayscale UI. No green.
bold=$'\033[1m'
dim=$'\033[2m'
grey=$'\033[38;5;244m'
white=$'\033[38;5;255m'
reset=$'\033[0m'

row() {
  local idx="$1" name="$2" value="$3" marker=" "
  [[ "$HD_SELECTED" -eq "$idx" ]] && marker=">"

  if [[ "$HD_SELECTED" -eq "$idx" ]]; then
    printf ' %b%s%b %b%-7s%b %s\n' "$white" "$marker" "$reset" "$bold" "$name" "$reset" "$value"
  else
    printf ' %b%s %-7s%b %s\n' "$dim" "$marker" "$name" "$reset" "$value"
  fi
}

draw_dashboard() {
  clear_screen
  printf '%b──────────────────────────────%b\n' "$grey" "$reset"
  printf '  %bHACKER DASHBOARD%b\n' "$bold" "$reset"
  printf '%b──────────────────────────────%b\n' "$grey" "$reset"
  row 0 'TARGET:' "$TARGET"
  row 1 'HUNTER:' "$HUNTER"
  printf '%b──────────────────────────────%b\n' "$grey" "$reset"
  printf '  %b↑/↓ j/k%b select   %bc%b copy   %be%b edit   %bq%b quit\n' \
    "$dim" "$reset" "$bold" "$reset" "$bold" "$reset" "$bold" "$reset"

  if [[ -n "$HD_STATUS" ]]; then
    printf '\n  %b%s%b\n' "$grey" "$HD_STATUS" "$reset"
  fi
}

read_key() {
  local key rest
  IFS= read -rsn1 key || return 1
  if [[ "$key" == $'\x1b' ]]; then
    IFS= read -rsn2 -t 0.05 rest || true
    key+="$rest"
  fi
  printf '%s' "$key"
}

copy_selected() {
  local name value
  name="$(selected_name)"
  value="$(selected_value)"

  # Copy should also refresh/export the shell and tmux environment.
  export_vars
  save_state

  if [[ -z "$value" ]]; then
    HD_STATUS="$name is empty; nothing copied"
    notify_parent_shell
    return 1
  fi

  if copy_clipboard "$value"; then
    HD_STATUS="Copied $name and exported TARGET/HUNTER"
  else
    HD_STATUS="Exported TARGET/HUNTER; clipboard fallback failed"
  fi

  notify_parent_shell
}

edit_selected() {
  local name current new_value
  name="$(selected_name)"
  current="$(selected_value)"

  clear_screen
  printf '%bEdit %s%b\n\n' "$bold" "$name" "$reset"
  printf 'Current: %s\n' "$current"
  printf 'New IP: '
  IFS= read -r new_value

  set_selected_value "$new_value"
  HD_STATUS="Updated $name and exported TARGET/HUNTER"
}

print_env() {
  load_state
  printf 'export TARGET=%s\n' "$(quote_shell "$TARGET")"
  printf 'export HUNTER=%s\n' "$(quote_shell "$HUNTER")"
}

usage() {
  cat <<'USAGE'
hacker-dash - minimal TARGET/HUNTER dashboard

Usage:
  ./hacker-dash.sh                    # tmux popup when inside tmux, otherwise inline UI
  source ./hacker-dash.sh             # same, and refreshes current shell variables after exit
  ./hacker-dash.sh --no-popup         # force inline UI
  ./hacker-dash.sh --popup            # force tmux popup UI
  ./hacker-dash.sh --print-env        # print export commands
  ./hacker-dash.sh --set TARGET VALUE # set TARGET
  ./hacker-dash.sh --set HUNTER VALUE # set HUNTER
  ./hacker-dash.sh --clear            # clear both values

Keys:
  ↑/↓ or j/k  select TARGET/HUNTER
  c           copy selected value and export TARGET/HUNTER
  e           edit selected value and export TARGET/HUNTER
  q           quit

Important:
  A normal executable cannot mutate its parent shell variables.
  Use `source ./hacker-dash.sh` or a shell function wrapper if you want
  the current pane's $TARGET and $HUNTER to update after the popup closes.
USAGE
}

run_ui() {
  load_state
  export_vars

  while true; do
    draw_dashboard
    local key
    key="$(read_key)" || return 0

    case "$key" in
      $'\x1b[A'|k|K) HD_SELECTED=0 ;;
      $'\x1b[B'|j|J) HD_SELECTED=1 ;;
      c|C) copy_selected ;;
      e|E) edit_selected ;;
      q|Q|$'\x03') clear_screen; return 0 ;;
    esac
  done
}

run_popup() {
  if [[ -z "${TMUX:-}" ]] || ! command -v tmux >/dev/null 2>&1; then
    run_ui
    local status=$?
    refresh_env_from_state
    return "$status"
  fi

  local path qpath cmd status
  path="$(script_path)"
  qpath="$(quote_shell "$path")"
  cmd="HACKER_DASH_IN_POPUP=1 HACKER_DASH_NOTIFY_PID=$$ bash $qpath --no-popup"

  tmux display-popup -E -w 46 -h 12 -T " hacker-dash " "$cmd"
  status=$?

  # If this script was sourced, this updates the current shell after popup exit.
  # If it was executed normally, it still keeps this process and tmux env fresh.
  refresh_env_from_state
  return "$status"
}

main() {
  case "${1:-}" in
    --help|-h)
      usage
      return 0
      ;;
    --print-env)
      print_env
      return 0
      ;;
    --set)
      load_state
      case "${2:-}" in
        TARGET) TARGET="${3:-}" ;;
        HUNTER) HUNTER="${3:-}" ;;
        *) printf 'Usage: %s --set TARGET|HUNTER VALUE\n' "$APP_NAME" >&2; return 2 ;;
      esac
      save_state
      export_vars
      notify_parent_shell
      return 0
      ;;
    --clear)
      TARGET=""
      HUNTER=""
      save_state
      export_vars
      notify_parent_shell
      return 0
      ;;
    --popup)
      run_popup
      return $?
      ;;
    --no-popup)
      run_ui
      local status=$?
      refresh_env_from_state
      return "$status"
      ;;
    *)
      if [[ -n "${TMUX:-}" && -z "${HACKER_DASH_IN_POPUP:-}" ]]; then
        run_popup
      else
        run_ui
        local status=$?
        refresh_env_from_state
        return "$status"
      fi
      ;;
  esac
}

main "$@"
finish $?
