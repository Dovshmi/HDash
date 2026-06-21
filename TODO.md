# Hacker Dash TODO

Deferred UX improvements to handle later, not in the current cleanup pass.

## Menu polish

- Final UI/look redesign should happen at the end, after the main features are added.
- Improve overall menu visual design so the UI feels cleaner and easier to scan.
- Fix jitter/flicker when moving up/down through menus.
  - Investigate whether full-screen redraws can be reduced or replaced with a lighter redraw strategy.
  - Keep terminal compatibility with tmux popup and normal terminal mode.
- Make menu spacing, labels, and helper text more consistent across main, run, cheats, shell, URL, doctor, and report screens.

## Cheats redesign

- Redesign the Cheats menu so it is not just another version of Run commands.
- Cheats should focus on copy-ready operator snippets, not commands that are better launched from Run.
- Possible cheat categories:
  - Environment/export snippets
  - Reverse shell payloads
  - Stabilization/PTY snippets
  - Common web payload templates
  - File transfer snippets
  - Listener one-liners
  - Report/notes templates only if not duplicating the report menu
- Keep the Run menu focused on launching tools; keep Cheats focused on copying reusable text.

## Scan output helper

- Add a helper for viewing existing scan outputs without leaving the dashboard.
- Detect common scan files under the current scan directory, for example:
  - scans/tcp.nmap
  - scans/rports.nmap
  - scans/allports.nmap
  - scans/gobuster.txt
  - scans/nikto.txt
  - scans/ffuf.json
  - scans/feroxbuster.txt
- Possible actions:
  - open with `less`
  - copy file path
  - show last modified scan files
  - add important output paths to the target notes/report

## Wordlist manager

- Add a wordlist picker for web fuzzing commands.
- Include common defaults when they exist, such as:
  - /usr/share/wordlists/dirbuster/directory-list-2.3-medium.txt
  - common SecLists Discovery/Web-Content paths
  - raft-small/common wordlists
- If the expected wordlist path does not exist, let the user choose or type a custom path.
- Validate custom paths before saving them.
- Save the chosen wordlist in state so gobuster/ffuf/feroxbuster reuse it.

## Better smart suggestions

- Improve Smart scans so suggested actions are ordered by detected service priority.
- Examples:
  - 80/443/8080 -> web actions first
  - 445/139 -> SMB actions
  - 21 -> FTP anonymous/script checks
  - 22 -> SSH scripts
  - 53 -> DNS enum
  - 3389 -> RDP checks
  - 3306/5432/6379/etc. -> database checks
- Keep nmap baseline actions visible even if no service-specific suggestions match.

## More service modules

- Add modules for commonly seen pentest/CTF services:
  - DNS: dig, dnsrecon, dnsenum
  - FTP: anonymous login check, safe nmap FTP scripts
  - SSH: ssh-audit if installed, nmap SSH scripts
  - RDP: nmap RDP scripts
  - LDAP/Kerberos/AD: safe enum helpers for domain boxes
  - SNMP: snmpwalk, onesixtyone
  - Databases: MySQL, PostgreSQL, Redis, MongoDB checks
- Each module should use safe, authorized, enumeration-focused commands.
- Add dependency doctor entries for any new optional tools.

## UX rules to preserve

- Backspace goes back from nested menus.
- `q` quits from any menu.
- Avoid duplicate feature entry points between main keys and nested menus.
- Keep Smart scans and All scans separated in the Run menu.
