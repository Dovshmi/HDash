# ⚡ Hacker Dashboard

A lightweight, TUI-based dashboard for managing `TARGET` and `HUNTER` IP addresses, designed for security researchers and CTF players.

It provides a fast way to switch between target IPs, copy them to the system clipboard, and export them as environment variables for other tools (like tmux, shells, or custom scripts) to use.

## 🚀 Features

- **Dual-Mode Implementation**:
  - **Go TUI**: A modern, polished interface built with [Bubble Tea](https://github.com/charmbracelet/bubbletea).
  - **Bash Script**: A lightweight shell implementation for maximum compatibility and direct shell environment integration.
- **Environment Integration**: Automatically exports `TARGET` and `HUNTER` variables to your current shell and tmux environment.
- **Clipboard Support**: Intelligent clipboard integration across Linux (Wayland/X11) and macOS, including OSC52 fallback for SSH/tmux sessions.
- **State Persistence**: Saves your IPs in `~/.config/hacker-dash/state.json` (Go) or `state.env` (Bash).

## 🛠 Installation

### Go Version
1. Clone the repo:
   ```bash
   git clone https://github.com/yourusername/hacker-dash.git
   cd hacker-dash
   ```
2. Build and install:
   ```bash
   go build -o hacker-dash main.go
   sudo mv hacker-dash /usr/local/bin/
   ```

### Bash Version
Simply copy the `hacker-dash.sh` script to your bin folder:
```bash
cp hacker-dash.sh ~/bin/hacker-dash
chmod +x ~/bin/hacker-dash
```
To use the interactive features that update your current shell, source it:
```bash
source ~/bin/hacker-dash
```

## ⌨️ Usage

- **Up/Down (j/k)**: Select between TARGET and HUNTER.
- **Enter**: Open action menu (Copy to Clipboard / Change IP).
- **e**: Quickly edit the selected IP.
- **q**: Quit.

## ⚙️ Shell Integration (Bash Version)
To make `hacker-dash` automatically update your current shell when you change an IP from a tmux popup, add this to your `.bashrc` or `.zshrc`:

```bash
# Reload hacker-dash state on USR1 signal
trap 'source ~/.config/hacker-dash/state.env 2>/dev/null' USR1
```
