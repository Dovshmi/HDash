#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

tmp_config="$(mktemp -d)"
command_runner=""
cleanup() {
  [[ -n "${command_runner:-}" ]] && rm -f "$command_runner"
  rm -rf "$tmp_config"
}
trap cleanup EXIT

run_hd() {
  env -u TARGET -u HUNTER -u URL -u RPORTS XDG_CONFIG_HOME="$tmp_config" ./hacker-dash.sh "$@"
}

assert_contains() {
  local haystack="$1" needle="$2"
  if [[ "$haystack" != *"$needle"* ]]; then
    printf 'Expected output to contain: %s\nOutput was:\n%s\n' "$needle" "$haystack" >&2
    exit 1
  fi
}

run_hd --clear >/dev/null
run_hd --set TARGET 10.10.10.10
run_hd --set HUNTER 10.10.14.2
run_hd --set URL http://10.10.10.10
run_hd --set RPORTS 22,80,445

doctor_output="$(run_hd --doctor)"
assert_contains "$doctor_output" "Dependency doctor"
assert_contains "$doctor_output" "Core tools"
assert_contains "$doctor_output" "Pentest tools"
assert_contains "$doctor_output" "rlwrap"

report_output="$(run_hd --report)"
assert_contains "$report_output" "Professional Pentest Brief"
assert_contains "$report_output" "Target: 10.10.10.10"
assert_contains "$report_output" "Detected services: SSH, Web, SMB"
assert_contains "$report_output" "Recommended next steps"

run_hd --set RPORTS 22,80
report_output="$(run_hd --report)"
assert_contains "$report_output" "4. SSH: capture host keys/algorithms"
if [[ "$report_output" == *"5. SSH:"* ]]; then
  printf 'Report step numbering skipped a number:\n%s\n' "$report_output" >&2
  exit 1
fi
run_hd --set RPORTS 22,80,445

source ./hacker-dash.sh --help >/dev/null
set -euo pipefail
TARGET=10.10.10.10
HUNTER=10.10.14.2
URL=http://10.10.10.10
RPORTS=22,80,445
service_summary="$(smart_service_summary)"
assert_contains "$service_summary" "SSH"
assert_contains "$service_summary" "Web"
assert_contains "$service_summary" "SMB"

preview_cmd="$(prepare_command "smoke" "echo ok")"
[[ "$preview_cmd" == "echo ok" ]]

command_runner="$(write_command_script "echo smoke-runner")"
[[ -n "$command_runner" ]]
[[ -x "$command_runner" ]]
runner_output="$(bash "$command_runner" <<<"")"
assert_contains "$runner_output" "Command: echo smoke-runner"

export HD_SMOKE_CONFIG="$tmp_config"
python3 - <<'PY'
import os
import pty
import select
import subprocess
import sys
import time

repo = os.getcwd()
tmp_config = os.environ["HD_SMOKE_CONFIG"]

def hd_env():
    env = os.environ.copy()
    for key in ("TARGET", "HUNTER", "URL", "RPORTS"):
        env.pop(key, None)
    env["XDG_CONFIG_HOME"] = tmp_config
    return env

def run_pty(keys, timeout=5):
    master, slave = pty.openpty()
    proc = subprocess.Popen(
        ["./hacker-dash.sh", "--no-popup"],
        cwd=repo,
        env=hd_env(),
        stdin=slave,
        stdout=slave,
        stderr=slave,
        close_fds=True,
    )
    os.close(slave)
    time.sleep(0.2)
    os.write(master, keys)
    out = b""
    deadline = time.time() + timeout
    try:
        while time.time() < deadline:
            ready, _, _ = select.select([master], [], [], 0.1)
            if ready:
                try:
                    chunk = os.read(master, 4096)
                except OSError:
                    break
                if not chunk:
                    break
                out += chunk
            if proc.poll() is not None:
                break
    finally:
        if proc.poll() is None:
            proc.terminate()
            time.sleep(0.2)
            if proc.poll() is None:
                proc.kill()
    return out.decode("utf-8", "ignore")

run_menu = run_pty(b"r\x7fq")
if "Run commands" not in run_menu or "Smart scans" not in run_menu or "All scans" not in run_menu:
    print(run_menu[-2000:])
    sys.exit("run menu Smart/All smoke failed")
if "Recon   " in run_menu or "Back\r\n" in run_menu or " Back\r\n" in run_menu:
    print(run_menu[-2000:])
    sys.exit("run menu still shows old category/back entries")

smart_menu = run_pty(b"r\r\x7fq")
if "Smart scans" not in smart_menu or "Showing only likely useful commands" not in smart_menu:
    print(smart_menu[-2000:])
    sys.exit("smart scans menu smoke failed")

all_menu = run_pty(b"rj\r\x7fq")
if "All scans" not in all_menu or "whatweb URL" not in all_menu or "nmap SMB enum scripts" not in all_menu:
    print(all_menu[-2000:])
    sys.exit("all scans menu smoke failed")

preview = run_pty(b"r\r\rq")
if "Preview command" not in preview or "nmap -sC -sV" not in preview:
    print(preview[-2000:])
    sys.exit("command preview UI smoke failed")

run_pty(b"u3q")
env_output = subprocess.check_output(
    ["./hacker-dash.sh", "--print-env"], cwd=repo, env=hd_env(), text=True
)
if "export URL=http://10.10.10.10:80" not in env_output:
    print(env_output)
    sys.exit("URL helper UI smoke failed")
PY

printf 'smoke tests passed\n'
