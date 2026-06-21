# Hacker Dashboard

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
- Press `e` to edit the selected value; on `RPORTS`, choose replace/add/delete
- Press `r` to open the command menu with arrow-key selection
- Commands launch in a normal terminal/tmux window, not inside the dashboard popup
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
- `e` - edit selected value and export vars; on `RPORTS`, choose replace/add/delete
- `r` - run command menu, then use `↑/↓` or `j/k` and `Enter`
- `q` - quit

Command menu:

Use `↑/↓` or `j/k`, then `Enter`. Number keys still work.

```text
Recon    nmap, rustscan
Web      whatweb, nikto, gobuster, ffuf, feroxbuster
SMB      smbclient, enum4linux-ng, nmap SMB scripts
Utility  ping, curl, nc
```

Recon subcommands:

```text
1 nmap quick scripts/services
2 nmap selected RPORTS
3 nmap all TCP ports
4 rustscan services
```

Web subcommands:

```text
1 whatweb URL
2 nikto URL
3 gobuster dir
4 ffuf dir
5 feroxbuster dir
```

SMB subcommands:

```text
1 smbclient list shares
2 enum4linux-ng
3 nmap SMB enum scripts
```

Utility subcommands:

```text
1 ping TARGET
2 curl headers/body URL
3 nc connect TARGET:first RPORT
```

## Variables

Set values from the UI with `e`. For `RPORTS`, `e` opens a menu to replace the list, add one port, or delete one port. You can also set values from the terminal:

```bash
hacker-dash --set TARGET 10.10.10.10
hacker-dash --set HUNTER 10.10.14.2
hacker-dash --set URL http://10.10.10.10
hacker-dash --set RPORTS 22,80,443
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
