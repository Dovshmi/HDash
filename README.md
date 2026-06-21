# Hacker Dashboard

A minimal Bash dashboard for managing `TARGET` and `HUNTER` IP addresses during security research, labs, and CTF work.

No Go version, no build step. This is Bash-only.

## Features

- Minimal modern terminal UI with no green theme
- Opens as a tmux popup automatically when you run it inside tmux
- Stores and reuses TARGET/HUNTER values
- Press `c` to copy the selected value and export TARGET/HUNTER
- Press `e` to edit the selected value and export TARGET/HUNTER
- Supports current-shell updates when sourced
- Supports tmux environment updates for new panes/windows
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

Inline/popup UI:

```bash
./hacker-dash.sh
```

Inside tmux this opens as a popup. Outside tmux it opens inline.

Tmux shortcut installed on this machine:

```bash
Ctrl-g
```

This opens Hacker Dash in a tmux popup. Press `q` to close it.

Force modes:

```bash
./hacker-dash.sh --popup
./hacker-dash.sh --no-popup
```

Keys:

- `↑/↓` or `j/k` - select TARGET/HUNTER
- `c` - copy selected value and export TARGET/HUNTER
- `e` - edit selected value and export TARGET/HUNTER
- `q` - quit

## Current shell environment

A normal executable cannot directly change the parent shell environment.

To update `TARGET` and `HUNTER` in your current shell after the popup closes, source it:

```bash
source ./hacker-dash.sh
```

Or if installed:

```bash
source ~/bin/hacker-dash
```

Recommended shell function wrapper for Bash or zsh:

```bash
hacker-dash() {
  source "$HOME/bin/hacker-dash" "$@"
}
```

The script detects zsh and runs the Bash UI safely, then imports the saved `TARGET` and `HUNTER` values back into your zsh session.

Add that function to `~/.bashrc` or `~/.zshrc`, then run:

```bash
hacker-dash
```

## Non-interactive commands

```bash
./hacker-dash.sh --set TARGET 10.10.10.10
./hacker-dash.sh --set HUNTER 10.10.14.2
./hacker-dash.sh --print-env
./hacker-dash.sh --clear
```

To import saved values into the current shell:

```bash
eval "$(./hacker-dash.sh --print-env)"
```
