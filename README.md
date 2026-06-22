# Hacker Dashboard

![Hacker Dash Preview](https://via.placeholder.com/800x400?text=Hacker+Dash+TUI+Screenshot)

A minimal Bash pentest dashboard for managing common target variables and launching common recon commands from tmux.

No Go version, no build step. This is Bash-only.

## Features

- Minimal modern terminal UI with no green theme
- Opens as a tmux popup with `Ctrl-g`
- Stores and exports:
  - `TARGET`
  - `HUNTER`
  - `URL`
  - `RPORTS` comma-separated ports, like `22,80,443,8080`
- Press `c` to copy the selected value
- Press `e` to edit the selected value; on `URL`, open URL workspace/manual edit; on `RPORTS`, choose replace/add/delete
- Press `r` to open a smart service-aware command menu with arrow-key selection
- Press `o` for the Operator Toolkit: shell/listener helpers, dependency doctor, and copy-ready operator snippets
- Press `p` for a smart professional pentest brief/report
- Commands launch in a normal terminal/tmux window, not inside the dashboard popup
- Every launched command shows a preview first: Enter runs, `e` edits, `c` copies, `b` backs out
- Press `b` or Backspace to go back from nested menus
- Check out the [examples/](examples/) folder for a sample professional report.
- Clipboard fallbacks for Wayland, X11, macOS, tmux, and OSC52
- State saved at `~/.config/hacker-dash/state.env`

## Install

From this folder:

```bash
chmod +x install.sh
./install.sh
```

This installs:

- `~/bin/hacker-dash`
- a tmux `Ctrl-g` popup binding in `~/.tmux.conf`

If `~/bin` is not in your PATH, add this to your shell config:

```bash
export PATH="$HOME/bin:$PATH"
```

## Usage

Inside tmux:

```text
Ctrl-g
```

Or run directly:

```bash
hacker-dash
```

Force modes:

```bash
hacker-dash --popup
hacker-dash --no-popup
```

## Keys

Main dashboard:

- `↑/↓` or `j/k` - select TARGET/HUNTER/URL/RPORTS
- `c` - copy selected value and export vars
- `e` - edit selected value and export vars; on `URL`, choose helper/manual edit; on `RPORTS`, choose replace/add/delete
- `r` - run command menu, then choose Smart scans or All scans
- `o` - Operator Toolkit for shells/listeners, dependency doctor, and copy-ready snippets
- `p` - professional report menu
- `b` or Backspace - go back from nested menus
- `q` - quit from any menu

Run menu:

```text
Smart scans  recommended commands from RPORTS/services
All scans    every scan/utility command in one list
```

Before a command runs, Hacker Dash shows a preview:

```text
Enter run   e edit   c copy   b/Backspace back   q quit
```

Smart scans are based on `RPORTS`:

```text
21       FTP checks
22       SSH nmap scripts
80/443   Web actions
139/445  SMB actions
```

Smart scans keep baseline nmap actions visible even when no services are detected.
All scans shows every command in one manual list.

All scan commands include:

```text
nmap quick scripts/services
nmap selected RPORTS
nmap all TCP ports
rustscan services
whatweb URL
nikto URL
gobuster dir
ffuf dir
feroxbuster dir
smbclient list shares
enum4linux-ng
nmap SMB enum scripts
ping TARGET
curl headers/body URL
nc connect TARGET:first RPORT
```

Operator Toolkit:

```text
Shell & listeners    listeners, reverse shells, PTY upgrade/stabilization snippets
Dependency doctor    check useful local dependencies; press d inside toolkit
Copy-ready snippets  export line and reusable scan/fuzz commands
```

URL workspace is available from the main dashboard by selecting `URL` and pressing `e`.
It supports both helper-generated URLs and manual URL editing.

Shell & listeners subcommands:

```text
1 nc listener
2 rlwrap nc listener
3 copy bash reverse shell using HUNTER/LPORT
4 copy Python PTY upgrade
5 copy shell stabilization steps
```

## Doctor and report

Check dependencies:

```bash
hacker-dash --doctor
```

Generate a smart markdown-style brief:

```bash
hacker-dash --report
```

From the Ctrl-g popup, press `d` for the dependency doctor or `p` to copy/save/preview the professional report. Saved reports go under `./reports/` in the current directory.

## Variables

Set values from the UI with `e`. For `RPORTS`, `e` opens a menu to replace the list, add one port, or delete one port. You can also set values from the terminal:

```bash
hacker-dash --set TARGET 10.10.10.10
hacker-dash --set HUNTER 10.10.14.2
hacker-dash --set URL http://10.10.10.10
hacker-dash --set RPORTS 22,80,443
hacker-dash --doctor
hacker-dash --report
```

Import saved values into the current shell:

```bash
eval "$(hacker-dash --print-env)"
```

Recommended shell function wrapper for Bash or zsh:

```bash
hacker-dash() {
  source "$HOME/bin/hacker-dash" "$@"
}
```

The script detects zsh and runs the Bash UI safely, then imports the saved variables back into your zsh session.

## Wordlists

Web commands use this default wordlist:

```bash
/usr/share/wordlists/dirbuster/directory-list-2.3-medium.txt
```

Override it for one run/session:

```bash
export WORDLIST=/path/to/wordlist.txt
```

## Notes

A normal executable cannot directly change the parent shell environment. Use the shell function wrapper above if you want `$TARGET`, `$HUNTER`, `$URL`, and `$RPORTS` updated in your current pane after the popup closes.
