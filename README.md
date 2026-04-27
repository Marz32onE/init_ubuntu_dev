# init_ubuntu_dev

A single-script Ubuntu dev environment bootstrap that installs and configures everything you need.

## What gets installed

| # | Tool | Notes |
|---|------|-------|
| 1 | **Zsh + Powerlevel10k** | via [zinit](https://github.com/zdharma-continuum/zinit) – no oh-my-zsh |
| 2 | **Go + golangci-lint** | latest stable Go; golangci-lint via official script |
| 3 | **Claude Code** | `@anthropic-ai/claude-code` (Anthropic CLI) |
| 4 | **Cursor** | `curl https://cursor.com/install -fsS | bash` |
| 5 | **RTK CLI** | Redux Toolkit CLI + config files for Claude Code & Cursor |
| 6 | **Claude plugins** | `superpowers` and `claude-hud` extensions |
| 7 | **Skill Caveman** | caveman skill registered for Claude Code & Cursor |
| 8 | **OpenSpec** | OpenAPI/OpenSpec CLI |

## Requirements

- Ubuntu 20.04 LTS or later (Debian-based)
- `sudo` access
- Internet connection

## Usage

```bash
git clone https://github.com/YOUR_USERNAME/init_ubuntu_dev.git
cd init_ubuntu_dev
chmod +x setup.sh
./setup.sh
```

After the script finishes:

```bash
exec zsh          # start zsh in the current terminal
p10k configure    # interactive Powerlevel10k prompt wizard
claude auth       # authenticate your Anthropic account
cursor            # launch the Cursor editor
```

## What happens step by step

1. **Prerequisites** – updates `apt` and installs `curl`, `git`, `build-essential`, etc.
2. **Zsh + Powerlevel10k** – installs `zsh`, sets it as your default shell, downloads the MesloLGS NF fonts, installs the `zinit` plugin manager, and appends a minimal `~/.zshrc` that loads Powerlevel10k plus `zsh-autosuggestions` / `zsh-syntax-highlighting`.
3. **Go** – downloads the latest stable tarball from `go.dev`, extracts to `/usr/local/go`, and sets `GOROOT`/`GOPATH`/`PATH` in both `~/.bashrc` and `~/.zshrc`.
4. **golangci-lint** – installed into `$GOPATH/bin` via the official install script.
5. **Node.js** – installed via `nvm` (LTS channel); required by Claude Code, RTK CLI, plugins and OpenSpec.
6. **Claude Code** – `npm install -g @anthropic-ai/claude-code`.
7. **Cursor** – official install script from `cursor.com`.
8. **RTK CLI** – `npm install -g rtk-cli`; writes config templates to `~/.config/claude/rtk.json` and `~/.cursor/User/rtk-settings.json`.
9. **Claude plugins** – attempts to install `superpowers` and `claude-hud` from npm and registers them via `claude extension install`.
10. **Skill Caveman** – installs the `skill-caveman` npm package, registers it with Claude Code, and writes a Cursor settings template.
11. **OpenSpec** – `npm install -g openspec`.

## Idempotent

Every step checks whether the tool is already installed before doing anything, so re-running `setup.sh` is safe.
