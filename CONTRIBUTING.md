# Contributing to Hacker Dash

First off, thank you for considering contributing to Hacker Dash! It's a tool built for speed and efficiency in security research.

## How to Contribute

### 1. Reporting Bugs
If you find a bug, please open an issue. Include:
- Your OS and shell (e.g., Kali Linux, zsh).
- Whether you are using tmux.
- The steps to reproduce the bug.
- The expected vs. actual output.

### 2. Developing Features
- **Maintain Simplicity**: The goal is to keep the tool "Bash-only" with no external dependencies besides standard Linux utilities.
- **TUI Consistency**: Follow the existing `menu_option` and `menu_header` patterns for any new menus.
- **Test First**: If you change the core logic, update `tests/smoke.sh` to ensure no regressions.

### 3. Submitting Changes
- Use clear, concise commit messages.
- If you are adding a new feature, please update the `README.md` to explain the new keybindings or options.
- Submit a Pull Request for review.

## Development Workflow
To test your changes locally:
```bash
chmod +x install.sh
./install.sh
# Run the tool
hacker-dash
# Run the test suite
bash tests/smoke.sh
```
