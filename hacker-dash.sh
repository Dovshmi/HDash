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
    --print-env|--help|-h|--set|--clear)
      bash "$_hd_self" "$@"
      _hd_rc=$?
      ;;
    *)
      if [ -n "${TMUX:-}" ] && [ -z "${HACKER_DASH_IN_POPUP:-}" ] && [ "${1:-}" != "--no-popup" ] && command -v tmux >/dev/null 2>&1; then
        _hd_q="$(printf '%q' "$_hd_self")"
        tmux display-popup -E -w 56 -h 16 -T " hacker-dash " "HACKER_DASH_IN_POPUP=1 bash $_hd_q --no-popup"
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
  printf '%b────────────────────────────────────────────%b\n' "$grey" "$reset"
  printf '  %b↑/↓ j/k%b select  %bc%b copy  %be%b edit  %br%b run  %bq%b quit\n' \
    "$dim" "$reset" "$bold" "$reset" "$bold" "$reset" "$bold" "$reset" "$bold" "$reset"

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
  IFS= read -r new_port
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
    printf '\n  %bEnter%b delete  %bb%b back\n' "$bold" "$reset" "$bold" "$reset"

    key="$(read_key)" || return
    case "$key" in
      $'\x1b[A'|k|K) (( selected > 0 )) && ((selected--)) ;;
      $'\x1b[B'|j|J) (( selected < max )) && ((selected++)) ;;
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
      b|B|q|Q) HD_STATUS="Delete cancelled"; return ;;
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
  IFS= read -r new_value
  set_rports_and_notify "$new_value"
  HD_STATUS="Replaced RPORTS and exported vars"
}

rports_menu() {
  local key selected=0 max=3
  while true; do
    menu_header "Manage RPORTS"
    printf '  Current: %s\n\n' "${RPORTS:-<empty>}"
    menu_option 0 "$selected" "Replace full list"
    menu_option 1 "$selected" "Add one port"
    menu_option 2 "$selected" "Delete one port"
    menu_option 3 "$selected" "Back"
    printf '\n  %b↑/↓ j/k%b select  %bEnter%b choose\n' "$dim" "$reset" "$bold" "$reset"

    key="$(read_key)" || return
    case "$key" in
      $'\x1b[A'|k|K) (( selected > 0 )) && ((selected--)) ;;
      $'\x1b[B'|j|J) (( selected < max )) && ((selected++)) ;;
      1) replace_rports; return ;;
      2) add_rport; return ;;
      3) delete_rport; return ;;
      4|b|B|q|Q) return ;;
      ''|$'\r'|$'\n')
        case "$selected" in
          0) replace_rports; return ;;
          1) add_rport; return ;;
          2) delete_rport; return ;;
          3) return ;;
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

  clear_screen
  printf '%bEdit %s%b\n\n' "$bold" "$name" "$reset"
  printf 'Current: %s\n' "$current"
  if [[ "$name" == "URL" ]]; then
    printf 'Example: http://10.10.10.10 or https://host:8443\n'
  fi
  printf 'New value: '
  IFS= read -r new_value

  set_selected_value "$new_value"
  HD_STATUS="Updated $name and exported vars"
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

menu_header() {
  clear_screen
  printf '%b────────────────────────────────────────────%b\n' "$grey" "$reset"
  printf '  %b%s%b\n' "$bold" "$1" "$reset"
  printf '%b────────────────────────────────────────────%b\n' "$grey" "$reset"
}

recon_menu() {
  local key selected=0 max=4
  while true; do
    menu_header "Recon commands"
    menu_option 0 "$selected" "nmap quick scripts/services"
    menu_option 1 "$selected" "nmap selected RPORTS"
    menu_option 2 "$selected" "nmap all TCP ports"
    menu_option 3 "$selected" "rustscan services"
    menu_option 4 "$selected" "Back"
    printf '\n  %b↑/↓ j/k%b select  %bEnter%b run\n' "$dim" "$reset" "$bold" "$reset"
    key="$(read_key)" || return
    case "$key" in
      $'\x1b[A'|k|K) (( selected > 0 )) && ((selected--)) ;;
      $'\x1b[B'|j|J) (( selected < max )) && ((selected++)) ;;
      1) run_nmap_quick; return ;;
      2) run_nmap_rports; return ;;
      3) run_nmap_allports; return ;;
      4) run_rustscan; return ;;
      5|b|B|q|Q) return ;;
      ''|$'\r'|$'\n')
        case "$selected" in
          0) run_nmap_quick; return ;;
          1) run_nmap_rports; return ;;
          2) run_nmap_allports; return ;;
          3) run_rustscan; return ;;
          4) return ;;
        esac
        ;;
    esac
  done
}

web_menu() {
  local key selected=0 max=5
  while true; do
    menu_header "Web commands"
    menu_option 0 "$selected" "whatweb URL"
    menu_option 1 "$selected" "nikto URL"
    menu_option 2 "$selected" "gobuster dir"
    menu_option 3 "$selected" "ffuf dir"
    menu_option 4 "$selected" "feroxbuster dir"
    menu_option 5 "$selected" "Back"
    printf '\n  %b↑/↓ j/k%b select  %bEnter%b run\n' "$dim" "$reset" "$bold" "$reset"
    key="$(read_key)" || return
    case "$key" in
      $'\x1b[A'|k|K) (( selected > 0 )) && ((selected--)) ;;
      $'\x1b[B'|j|J) (( selected < max )) && ((selected++)) ;;
      1) run_whatweb; return ;;
      2) run_nikto; return ;;
      3) run_gobuster_dir; return ;;
      4) run_ffuf_dir; return ;;
      5) run_feroxbuster; return ;;
      6|b|B|q|Q) return ;;
      ''|$'\r'|$'\n')
        case "$selected" in
          0) run_whatweb; return ;;
          1) run_nikto; return ;;
          2) run_gobuster_dir; return ;;
          3) run_ffuf_dir; return ;;
          4) run_feroxbuster; return ;;
          5) return ;;
        esac
        ;;
    esac
  done
}

smb_menu() {
  local key selected=0 max=3
  while true; do
    menu_header "SMB commands"
    menu_option 0 "$selected" "smbclient list shares"
    menu_option 1 "$selected" "enum4linux-ng"
    menu_option 2 "$selected" "nmap SMB enum scripts"
    menu_option 3 "$selected" "Back"
    printf '\n  %b↑/↓ j/k%b select  %bEnter%b run\n' "$dim" "$reset" "$bold" "$reset"
    key="$(read_key)" || return
    case "$key" in
      $'\x1b[A'|k|K) (( selected > 0 )) && ((selected--)) ;;
      $'\x1b[B'|j|J) (( selected < max )) && ((selected++)) ;;
      1) run_smbclient; return ;;
      2) run_enum4linux; return ;;
      3) run_nmap_smb; return ;;
      4|b|B|q|Q) return ;;
      ''|$'\r'|$'\n')
        case "$selected" in
          0) run_smbclient; return ;;
          1) run_enum4linux; return ;;
          2) run_nmap_smb; return ;;
          3) return ;;
        esac
        ;;
    esac
  done
}

utils_menu() {
  local key selected=0 max=3
  while true; do
    menu_header "Utility commands"
    menu_option 0 "$selected" "ping TARGET"
    menu_option 1 "$selected" "curl headers/body URL"
    menu_option 2 "$selected" "nc connect TARGET:first RPORT"
    menu_option 3 "$selected" "Back"
    printf '\n  %b↑/↓ j/k%b select  %bEnter%b run\n' "$dim" "$reset" "$bold" "$reset"
    key="$(read_key)" || return
    case "$key" in
      $'\x1b[A'|k|K) (( selected > 0 )) && ((selected--)) ;;
      $'\x1b[B'|j|J) (( selected < max )) && ((selected++)) ;;
      1) run_ping; return ;;
      2) run_curl_headers; return ;;
      3) run_nc_connect; return ;;
      4|b|B|q|Q) return ;;
      ''|$'\r'|$'\n')
        case "$selected" in
          0) run_ping; return ;;
          1) run_curl_headers; return ;;
          2) run_nc_connect; return ;;
          3) return ;;
        esac
        ;;
    esac
  done
}

command_menu() {
  local key selected=0 max=4
  while true; do
    menu_header "Run commands"
    menu_option 0 "$selected" "Recon    nmap, rustscan"
    menu_option 1 "$selected" "Web      whatweb, nikto, gobuster, ffuf, ferox"
    menu_option 2 "$selected" "SMB      smbclient, enum4linux-ng, nmap smb"
    menu_option 3 "$selected" "Utility  ping, curl, nc"
    menu_option 4 "$selected" "Back"
    printf '\n  %b↑/↓ j/k%b select  %bEnter%b choose\n' "$dim" "$reset" "$bold" "$reset"
    if [[ -n "$HD_STATUS" ]]; then
      printf '\n  %b%s%b\n' "$grey" "$HD_STATUS" "$reset"
    fi

    key="$(read_key)" || return
    case "$key" in
      $'\x1b[A'|k|K) (( selected > 0 )) && ((selected--)) ;;
      $'\x1b[B'|j|J) (( selected < max )) && ((selected++)) ;;
      1) recon_menu ;;
      2) web_menu ;;
      3) smb_menu ;;
      4) utils_menu ;;
      5|b|B|q|Q) return ;;
      ''|$'\r'|$'\n')
        case "$selected" in
          0) recon_menu ;;
          1) web_menu ;;
          2) smb_menu ;;
          3) utils_menu ;;
          4) return ;;
        esac
        ;;
    esac
    [[ "$HD_EXIT_AFTER_COMMAND" -eq 1 ]] && return
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

Main keys:
  ↑/↓ or j/k  select TARGET/HUNTER/URL/RPORTS
  c           copy selected value and export vars
  e           edit selected value; RPORTS opens add/delete/replace menu
  r           run command menu; choose with ↑/↓ or j/k, Enter to run
  q           quit

Command menu:
  Use ↑/↓ or j/k, then Enter. Number keys still work.
  Recon       nmap quick, nmap RPORTS, nmap all ports, rustscan
  Web         whatweb, nikto, gobuster, ffuf, feroxbuster
  SMB         smbclient, enum4linux-ng, nmap SMB scripts
  Utility     ping, curl, nc

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

  while true; do
    draw_dashboard
    local key
    key="$(read_key)" || return 0

    case "$key" in
      $'\x1b[A'|k|K) (( HD_SELECTED > 0 )) && ((HD_SELECTED--)) ;;
      $'\x1b[B'|j|J) (( HD_SELECTED < 3 )) && ((HD_SELECTED++)) ;;
      c|C) copy_selected ;;
      e|E) edit_selected ;;
      r|R) command_menu; [[ "$HD_EXIT_AFTER_COMMAND" -eq 1 ]] && return 0 ;;
      q|Q|$'\x03') clear_screen; return 0 ;;
    esac
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

  tmux display-popup -E -w 56 -h 16 -T " hacker-dash " "$cmd"
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
