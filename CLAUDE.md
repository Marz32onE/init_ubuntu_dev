# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Single-file Ubuntu dev environment bootstrap. One script (`setup.sh`) installs and configures a full dev toolchain on Ubuntu 20.04+.

## Running the script

```bash
chmod +x setup.sh
./setup.sh
```

Re-running is safe — every step guards with `command -v` or file-existence checks before acting.

## Script structure

`setup.sh` is organized as discrete `install_*` functions called sequentially from `main()`:

| Function | What it does |
|---|---|
| `install_prerequisites` | apt update + base packages |
| `install_zsh_p10k` | zsh, direct-clone Powerlevel10k + plugins, MesloLGS fonts, `~/.zshrc` config (p10k instant prompt prepended) |
| `install_jq` | Latest jq binary → `/usr/local/bin` (GitHub release; fallback to apt) |
| `install_go` / `install_golangci_lint` | Latest Go tarball → `/usr/local/go`; symlinks in `/usr/local/bin`; golangci-lint → `/usr/local/bin` |
| `install_nodejs` | nvm → Node LTS + TypeScript (`tsc`) global |
| `install_claude_code` | Native installer (`claude.ai/install.sh`) → `~/.local/bin` |
| `install_cursor` | Official `cursor.com/install` script |
| `install_rtk` | RTK (Rust Token Killer) installer → `~/.local/bin` |
| `install_claude_plugins` | superpowers + claude-hud + claude-code-setup via `claude extension install` |
| `install_skill_caveman` | skill-caveman npm install + `claude skill install caveman` |
| `install_openspec` | openspec npm install |
| `install_git_config` | Sets git global `user.email` / `user.name` |
| `install_repo` | Clones `otel-traces-test` → `~/Documents/otel-traces-test` |

## Key helpers

- `append_once <file> <marker> <content>` — appends a block to a shell rc file only if the marker string isn't already present. Used to keep `~/.bashrc` and `~/.zshrc` idempotent.
- `npm_install_try <label> <pkg1> <pkg2> ...` — tries npm package names in order, returns 0 on first success. Used for packages with uncertain/multiple registry names.
- `npm_any_installed <pkg1> <pkg2> ...` — checks `npm list -g` for any candidate; used as the idempotency guard before `npm_install_try`.
- `_ensure_nvm` — sources `~/.nvm/nvm.sh` in the current shell; called at the top of any function that needs `npm`/`node`.

## Extending the script

To add a new tool: write an `install_<tool>()` function following the pattern above (idempotency guard → install → log_success), then add a call to it in `main()`.

## Shell rc patching

Go env vars are written to both `~/.bashrc` and `~/.zshrc` via `append_once`. Zsh plugin sourcing uses `env-init:` prefixed markers. The marker string is the first line of the block — changing it will cause duplicate entries on re-run.
