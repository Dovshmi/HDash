# 🧭 HDash — Hacker Dashboard

<div align="center">
  <img src="https://img.shields.io/badge/Bash-4EAA25?style=for-the-badge&logo=gnubash&logoColor=white" alt="Bash" />
  <img src="https://img.shields.io/badge/tmux-1BB91F?style=for-the-badge&logo=tmux&logoColor=white" alt="tmux" />
  <img src="https://img.shields.io/badge/Linux-Terminal-111827?style=for-the-badge&logo=linux&logoColor=white" alt="Linux Terminal" />
  <img src="https://img.shields.io/badge/No_Build-Step-0F172A?style=for-the-badge" alt="No Build Step" />
  <img src="https://img.shields.io/badge/GitHub_Actions-2088FF?style=for-the-badge&logo=github-actions&logoColor=white" alt="GitHub Actions" />
  <img src="https://img.shields.io/badge/Pentest_Workflow-475569?style=for-the-badge" alt="Pentest Workflow" />
  <img src="https://img.shields.io/badge/tmux_Popup-Ctrl--g-64748B?style=for-the-badge" alt="tmux Ctrl-g Popup" />
  <img src="https://img.shields.io/badge/License-Not_Specified-6B7280?style=for-the-badge" alt="License Not Specified" />
</div>

<div align="center">
  <p><strong>A minimal Bash + tmux dashboard for managing target variables, launching authorized recon workflows, and keeping pentest notes organized from the terminal.</strong></p>
  <p>
    <a href="https://github.com/Dovshmi/HDash"><strong>GitHub Repository</strong></a>
  </p>
</div>

---

## Overview

**HDash** is a lightweight terminal dashboard built for tmux-based security labs, CTF boxes, and authorized internal testing workflows. It keeps the most-used target variables in one place — `TARGET`, `HUNTER`, `URL`, and `RPORTS` — and exposes a keyboard-driven interface for editing, copying, exporting, and using those values during a session.

The project is intentionally simple: it is a Bash script, not a Go/Rust/Python application, and it does not require a build step. The goal is speed, repeatability, and a cleaner workflow inside tmux.

> **Authorized use only:** this tool is intended for systems you own, lab environments, CTF platforms, or engagements where you have explicit permission to test.

---

## Product Goals

- Keep target context visible and easy to update during terminal work.
- Reduce repeated typing of IP addresses, listener IPs, URLs, and discovered ports.
- Launch common recon actions from a predictable tmux workflow.
- Provide a clean command-preview step before anything runs.
- Keep the tool portable, readable, and dependency-light.
- Avoid a heavy framework, database, or build process.

---

## Core Features

### Dashboard Experience

- **tmux popup workflow** opened with `Ctrl-g` after installation.
- **Minimal grayscale terminal UI** designed to stay readable without the classic neon-green theme.
- **Persistent state** stored under `~/.config/hacker-dash/state.env`.
- **Target variable management** for:
  - `TARGET`
  - `HUNTER`
  - `URL`
  - `RPORTS`
- **Clipboard support** with fallbacks for Wayland, X11, macOS, tmux buffer, and OSC52.
- **Nested menu navigation** with arrow keys, `j/k`, Backspace, and `b`.
- **Shell import wrapper** for bringing saved variables back into the current Bash or zsh session.

### Workflow Helpers

- **Smart service summary** based on `RPORTS` and URL state.
- **Smart scan menu** that surfaces relevant actions based on detected service categories.
- **All scans menu** for manually choosing from the available workflow actions.
- **Command preview screen** before launching a command.
- **Edit-before-run flow** for adjusting prepared commands safely.
- **Operator Toolkit** for shell/listener helpers, dependency checks, and reusable snippets.
- **Professional report/brief generator** for summarizing target context and recommended next steps.

### Safety and Control

HDash does not silently execute selected actions. Before launching a prepared command, it shows a preview with options to run, edit, copy, or go back.

---

## Tech Stack

| Area | Technology |
| :--- | :--- |
| Runtime | Bash |
| Terminal Multiplexer | tmux |
| Interface | ANSI terminal UI |
| State Storage | Shell `state.env` file |
| Clipboard Fallbacks | Wayland, X11, macOS, tmux buffer, OSC52 |
| Tests | Bash smoke tests + Python PTY checks |
| CI | GitHub Actions |
| Build Step | None |

---

## Project Structure

```text
HDash/
├── .github/
│   └── workflows/
│       └── ci.yml          # GitHub Actions smoke-test workflow
├── examples/               # Example output/report material, if included
├── tests/
│   └── smoke.sh            # CLI and interactive smoke tests
├── hacker-dash.sh          # Main dashboard script
├── install.sh              # Installer for ~/bin/hacker-dash and tmux binding
└── README.md
```

---

## Requirements

Required:

- `bash`
- `tmux`

Recommended tools depend on the workflow you want to use. HDash includes a dependency doctor to show which local tools are available and which are missing.

Useful optional tools include:

- `curl`
- `nc`
- `rlwrap`
- `nmap`
- `rustscan`
- `whatweb`
- `nikto`
- `gobuster`
- `ffuf`
- `feroxbuster`
- `smbclient`
- `enum4linux-ng`
- `wl-copy`, `xclip`, `xsel`, or `pbcopy` for clipboard integration

---

## Installation

Clone the repository:

```bash
git clone https://github.com/Dovshmi/HDash.git
cd HDash
```

Run the installer:

```bash
chmod +x install.sh
./install.sh
```

The installer copies the dashboard to:

```text
~/bin/hacker-dash
```

It also writes a managed `Ctrl-g` tmux popup binding into:

```text
~/.tmux.conf
```

If `~/bin` is not already in your shell path, add this to your shell configuration:

```bash
export PATH="$HOME/bin:$PATH"
```

Then reload your shell or start a new terminal session.

---

## Usage

Open HDash inside tmux:

```text
Ctrl-g
```

Run it directly:

```bash
hacker-dash
```

Force popup or non-popup mode:

```bash
hacker-dash --popup
hacker-dash --no-popup
```

Set values from the command line:

```bash
hacker-dash --set TARGET 10.10.10.10
hacker-dash --set HUNTER 10.10.14.2
hacker-dash --set URL http://10.10.10.10
hacker-dash --set RPORTS 22,80,443
```

Print saved variables for shell import:

```bash
hacker-dash --print-env
```

Import the saved values into the current shell:

```bash
eval "$(hacker-dash --print-env)"
```

---

## Recommended Shell Wrapper

A normal executable cannot directly modify the environment of the parent shell. For the smoothest workflow, define `hacker-dash` as a shell function in Bash or zsh:

```bash
hacker-dash() {
  source "$HOME/bin/hacker-dash" "$@"
}
```

With this wrapper, saved `TARGET`, `HUNTER`, `URL`, and `RPORTS` values can be imported back into the current pane after the dashboard closes.

---

## Keyboard Controls

### Main Dashboard

| Key | Action |
| :--- | :--- |
| `↑/↓` or `j/k` | Move between dashboard fields. |
| `e` | Edit selected value. |
| `c` | Copy selected value and export variables. |
| `r` | Open the run menu. |
| `o` | Open the Operator Toolkit. |
| `p` | Open the professional report menu. |
| `b` or Backspace | Go back from nested menus. |
| `q` | Quit. |

### Command Preview

| Key | Action |
| :--- | :--- |
| Enter | Run the prepared command. |
| `e` | Edit the prepared command. |
| `c` | Copy the prepared command. |
| `b` or Backspace | Cancel and go back. |
| `q` | Quit. |

---

## Dependency Doctor and Reports

Run the dependency doctor:

```bash
hacker-dash --doctor
```

Generate a markdown-style professional brief:

```bash
hacker-dash --report
```

Inside the popup, use the Operator Toolkit and report menu for the same workflow from the interface.

---

## State and Configuration

HDash saves state here:

```text
~/.config/hacker-dash/state.env
```

The saved file contains exported shell variables for the current working context. File permissions are tightened by the script when saved.

Managed tmux configuration is written between these markers:

```text
# BEGIN hacker-dash tmux
# END hacker-dash tmux
```

This makes the installer safe to rerun without duplicating the binding.

---

## Quality and CI

The repository includes a GitHub Actions workflow that runs smoke tests on pushes and pull requests to `main`.

The smoke test coverage includes:

- CLI state commands.
- Dependency doctor output.
- Professional report output.
- Smart service summary behavior.
- tmux-style interactive menu checks through a PTY harness.
- Installer-related workflow assumptions.

Run the local smoke tests with:

```bash
chmod +x tests/smoke.sh
./tests/smoke.sh
```

---

## Design Notes

- **Bash-first:** keep the tool easy to audit and modify.
- **tmux-native:** HDash is designed around terminal workflows, not browser dashboards.
- **Preview before action:** commands are shown before they run.
- **No build process:** clone, install, and use.
- **Low visual noise:** the UI intentionally avoids a loud theme.
- **Session portability:** state is stored in a small shell-compatible file.

---

## Roadmap Ideas

Potential future improvements:

- Add a real screenshot or animated terminal demo to the README.
- Add a formal license file.
- Add more test coverage for installer edge cases.
- Add configurable key binding support.
- Add export profiles for different labs or boxes.
- Add optional template customization for generated reports.

---

## License

No license file is currently included in the repository. Add a `LICENSE` file if you want others to clearly know how they may use, modify, or redistribute the project.

---

<div align="center">
  Built for fast terminal workflow during authorized security labs and testing.<br />
  By Rony Shmidov
</div>
