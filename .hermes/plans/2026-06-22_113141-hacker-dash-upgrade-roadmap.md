# Hacker Dash Upgrade Roadmap Plan

> **For Hermes:** Approval-gated plan. Do not edit production code until the user chooses the first upgrade slice.

**Goal:** Upgrade Hacker Dash in small, testable steps based on `TODO.md`, while preserving existing tmux popup behavior, Backspace navigation, q-to-quit, Smart/All scan separation, and Bash-only portability.

**Architecture:** Keep the single-file Bash app for now (`hacker-dash.sh`) and add features by extracting small reusable helpers inside that file rather than introducing a build system. Expand `tests/smoke.sh` for each UI/menu behavior before implementation. Update `README.md` only after a feature is implemented and verified.

**Tech Stack:** Bash, tmux popup integration, Python stdlib only inside smoke tests, GitHub Actions shell checks.

---

## Current context

- Main app: `hacker-dash.sh` (1668 lines)
- Installer: `install.sh`
- Tests: `tests/smoke.sh`
- CI: `.github/workflows/ci.yml`
- Roadmap source: `TODO.md`
- Baseline verification passed before this plan:
  - `bash -n hacker-dash.sh`
  - `bash -n install.sh`
  - `bash tests/smoke.sh` -> `smoke tests passed`

Key existing areas:
- State/env: `hacker-dash.sh:53-180`
- UI primitives: `hacker-dash.sh:236-359`, `1051-1056`
- Service detection: `hacker-dash.sh:361-438`
- Doctor: `hacker-dash.sh:440-511`
- Run commands: `hacker-dash.sh:807-906`
- Cheats: `hacker-dash.sh:964-987`, `1356-1391`
- Reports: `hacker-dash.sh:989-1049`, `1430-1469`
- Menus: `hacker-dash.sh:1058-1501`
- CLI/main: `hacker-dash.sh:1503-1668`

## Proposed priority order

1. Scan output helper
2. Wordlist manager
3. Cheats redesign
4. Better smart suggestions + more service modules
5. Menu polish / flicker cleanup last

Reasoning:
- Scan output helper is useful, contained, and has low risk.
- Wordlist manager removes repeated configuration and supports later web features.
- Cheats redesign is bigger UX work; best after scan/wordlist primitives exist.
- Service modules and smart ordering should be done together so menus do not become messy.
- Visual redesign/flicker should happen last, matching `TODO.md`.

---

## Phase 1: Scan output helper

**Objective:** Add a dashboard menu to view/copy common scan output paths without leaving Hacker Dash.

**Likely files:**
- Modify: `hacker-dash.sh`
- Modify: `tests/smoke.sh`
- Modify after verification: `README.md`

**Proposed UX:**
- Add main key `s` = scan outputs.
- Menu title: `Scan outputs`.
- Detect files under `./scans/`:
  - `tcp.nmap`, `rports.nmap`, `allports.nmap`, `gobuster.txt`, `nikto.txt`, `ffuf.json`, `feroxbuster.txt`, `smb.nmap`, `ssh.nmap`, `ftp.nmap`
- For each detected file show basename and modified time if available.
- Actions:
  - Enter: open selected file in `less` via `launch_terminal_command` or inline fallback if not in tmux.
  - `c`: copy selected file path.
  - `a`: append selected path to a saved report note only if we add notes later; defer for now.
  - Backspace/q behavior unchanged.

**Implementation tasks:**
1. Add helper functions near report/command helpers:
   - `scan_dir_path`
   - `scan_candidate_files`
   - `scan_output_labels`
   - `copy_scan_path`
   - `open_scan_output`
2. Add `scan_outputs_menu` near other menus.
3. Add main key `s|S` in `run_ui` and help text in `draw_dashboard` + `usage`.
4. Add smoke tests:
   - create temporary `scans/tcp.nmap` and `scans/gobuster.txt`
   - open `s` menu in PTY and assert `Scan outputs` plus filenames appear
   - assert empty scans directory shows a friendly message
5. Run:
   - `bash -n hacker-dash.sh install.sh tests/smoke.sh`
   - `bash tests/smoke.sh`

**Risks/open questions:**
- Should Enter open `less` in the same popup or a tmux window? Recommendation: tmux window, same as command launch, to keep popup UI stable.
- Should scan directory always be `./scans`, or configurable later? Recommendation: keep `./scans` for now.

---

## Phase 2: Wordlist manager

**Objective:** Let the user choose and persist a wordlist used by gobuster/ffuf/feroxbuster.

**Likely files:**
- Modify: `hacker-dash.sh`
- Modify: `tests/smoke.sh`
- Modify after verification: `README.md`

**Proposed state change:**
- Add `WORDLIST` to saved state next to `TARGET`, `HUNTER`, `URL`, `RPORTS`.
- Keep env override support: if existing shell `WORDLIST` is set, load it initially; if app saves it, print/export it from `--print-env`.

**Proposed UX:**
- Add main key `w` = wordlist.
- Menu options:
  - common dirbuster medium path
  - common SecLists paths if they exist
  - custom path
  - clear saved wordlist / use default
- Validate custom paths with `[[ -f "$path" ]]` before saving.
- Show status if no common paths exist.

**Implementation tasks:**
1. Add `WORDLIST` variable and save/load/export/print support.
2. Add `default_wordlist` and `selected_wordlist_expr` helpers so command generation stays DRY.
3. Update `run_gobuster_dir`, `run_ffuf_dir`, `run_feroxbuster`, `cheat_gobuster`, `cheat_ffuf` to use saved `WORDLIST` with fallback.
4. Add `wordlist_menu` and main key `w|W`.
5. Add tests for:
   - `--set WORDLIST /tmp/list` if we choose to expose CLI set support
   - `--print-env` includes WORDLIST
   - generated report/cheat commands use the saved wordlist behavior
6. Run syntax and smoke tests.

**Risks/open questions:**
- Should `--set WORDLIST` be allowed? Recommendation: yes, consistent with other state variables.
- If a saved wordlist path later disappears, should commands warn or still run? Recommendation: warn in UI/menu, but generated commands can still fall back to default only when WORDLIST is empty.

---

## Phase 3: Cheats redesign

**Objective:** Make Cheats copy-ready operator snippets, not duplicate Run commands.

**Likely files:**
- Modify: `hacker-dash.sh`
- Modify: `tests/smoke.sh`
- Modify after verification: `README.md`

**Proposed categories:**
- Environment/export snippets
- Reverse shell payloads
- Stabilization/PTY snippets
- File transfer snippets
- Listener one-liners
- Common web payload templates

**Implementation tasks:**
1. Keep existing direct cheat helpers as reusable snippet functions where useful.
2. Replace flat `cheats_menu` with a category menu.
3. Add submenus with copy actions only; do not launch tools here.
4. Keep listener launching in Shell helper, not Cheats.
5. Add PTY smoke tests for category names and one submenu.
6. Update README feature/key descriptions.
7. Run syntax and smoke tests.

**Risks/open questions:**
- How offensive should payload templates be? Recommendation: keep to common authorized CTF/pentest snippets and avoid destructive payloads.

---

## Phase 4: Better smart suggestions + service modules

**Objective:** Expand service-aware suggestions and order them by priority.

**Likely files:**
- Modify: `hacker-dash.sh`
- Modify: `tests/smoke.sh`
- Modify after verification: `README.md`

**Service additions:**
- DNS: `dig`, `dnsrecon`, `dnsenum`
- FTP: anonymous check and safe nmap scripts
- SSH: `ssh-audit` if installed, nmap scripts
- RDP: nmap RDP scripts
- LDAP/Kerberos/AD: safe enum helpers only
- SNMP: `snmpwalk`, `onesixtyone`
- Databases: MySQL, PostgreSQL, Redis, MongoDB basic checks

**Implementation tasks:**
1. Add port detector helpers for DNS/RDP/LDAP/Kerberos/SNMP/databases.
2. Add command functions one service at a time.
3. Add doctor entries for optional tools as each command is added.
4. Refactor `smart_menu` construction so service sections are ordered:
   - Web first for 80/443/8080/etc.
   - SMB next for 445/139
   - DNS/FTP/SSH/RDP/AD/SNMP/DB after that
   - baseline nmap actions always visible
5. Add smoke tests for service summary and smart menu ordering.
6. Run syntax and smoke tests.

**Risks/open questions:**
- Some checks may be intrusive depending on scope. Recommendation: label all as enum/safe, keep brute-force out.
- AD/Kerberos helpers need careful UX so domain inputs are not guessed incorrectly.

---

## Phase 5: Menu polish / flicker cleanup

**Objective:** Improve consistency and reduce jitter after functional changes are stable.

**Likely files:**
- Modify: `hacker-dash.sh`
- Modify: `tests/smoke.sh` only if behavior changes

**Implementation tasks:**
1. Audit all menu helper text and labels for consistency.
2. Consider a lighter redraw helper, but preserve tmux popup compatibility.
3. Standardize menu heights/spacing after new menus are added.
4. Run interactive smoke tests in normal terminal and tmux popup.
5. Run syntax and smoke tests.

**Risks/open questions:**
- Flicker fixes can break terminal compatibility. This should stay last.

---

## Validation for every phase

Run before reporting done:

```bash
bash -n hacker-dash.sh install.sh tests/smoke.sh
bash tests/smoke.sh
git diff --check
```

For UI phases, also run at least one PTY smoke path in `tests/smoke.sh` and manually inspect if needed:

```bash
./hacker-dash.sh --no-popup
```

No commits or pushes unless the user explicitly asks.

---

## Recommended first decision

Start with Phase 1: Scan output helper.

It is the smallest useful feature from the TODO list, it touches a focused area of the app, and it gives us a pattern for adding future menus/tests safely.
