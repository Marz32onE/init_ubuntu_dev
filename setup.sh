#!/usr/bin/env bash
# Bootstrap dev environment: zsh + Powerlevel10k, Go, jq, TypeScript (tsc), Cursor 3.1, Claude Code CLI, RTK, git, clone repo.
# `sh init.sh` uses dash on Debian/Ubuntu; re-exec with bash (this script needs pipefail and [[ ]]).
if [ -z "${BASH_VERSION:-}" ]; then
  exec /usr/bin/env bash "$0" "$@"
fi
set -euo pipefail

SUDO=""
if [[ "${EUID:-0}" -ne 0 ]]; then
  SUDO="sudo"
fi

log() { printf '%s\n' "$*"; }

die() { log "ERROR: $*"; exit 1; }

map_arch() {
  case "$(uname -m)" in
    x86_64)  echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    *) die "unsupported architecture: $(uname -m)" ;;
  esac
}

map_cursor_arch() {
  case "$(uname -m)" in
    x86_64)  echo "x64" ;;
    aarch64|arm64) echo "arm64" ;;
    *) die "unsupported architecture: $(uname -m)" ;;
  esac
}

GOARCH="$(map_arch)"
CURSOR_ARCH="$(map_cursor_arch)"

# --- 1) Base packages (Debian/Ubuntu) ---
if command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  $SUDO apt-get update -qq
  $SUDO apt-get install -y \
    zsh git curl wget ca-certificates gnupg unzip \
    build-essential
else
  die "This script expects apt-get (Debian/Ubuntu). Install zsh/git/curl manually on other distros."
fi

# --- 2) Zsh plugins: Powerlevel10k + autosuggestions + syntax highlighting (no Oh My Zsh) ---
ZSH_PLUGINS_DIR="${HOME}/.config/zsh/plugins"
mkdir -p "${ZSH_PLUGINS_DIR}"

if [[ ! -d "${ZSH_PLUGINS_DIR}/powerlevel10k" ]]; then
  git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "${ZSH_PLUGINS_DIR}/powerlevel10k"
fi
if [[ ! -d "${ZSH_PLUGINS_DIR}/zsh-autosuggestions" ]]; then
  git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions "${ZSH_PLUGINS_DIR}/zsh-autosuggestions"
fi
if [[ ! -d "${ZSH_PLUGINS_DIR}/zsh-syntax-highlighting" ]]; then
  git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting "${ZSH_PLUGINS_DIR}/zsh-syntax-highlighting"
fi

ZSHRC="${HOME}/.zshrc"
[[ -f "${ZSHRC}" ]] || touch "${ZSHRC}"

# Powerlevel10k instant prompt — must be first in .zshrc
if ! grep -q 'p10k-instant-prompt' "${ZSHRC}"; then
  _p10k_tmp="$(mktemp)"
  cat >"${_p10k_tmp}" <<'ZSHINSTANT'
# Enable Powerlevel10k instant prompt (quiet mode)
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

ZSHINSTANT
  cat "${ZSHRC}" >>"${_p10k_tmp}"
  mv "${_p10k_tmp}" "${ZSHRC}"
fi

# Source plugins directly (idempotent via marker)
if ! grep -q 'env-init: zsh plugins' "${ZSHRC}" 2>/dev/null; then
  cat >> "${ZSHRC}" <<'ZSHPLUGINS'

# env-init: zsh plugins
source "$HOME/.config/zsh/plugins/powerlevel10k/powerlevel10k.zsh-theme"
source "$HOME/.config/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh"
source "$HOME/.config/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh
ZSHPLUGINS
fi

# Claude Code installs to ~/.local/bin; the native installer may not persist PATH for zsh (see anthropics/claude-code#21069).
mkdir -p "${HOME}/.local/bin"
if [[ -f "${ZSHRC}" ]] && ! grep -q 'env-init: user local bin' "${ZSHRC}" 2>/dev/null; then
  printf '\n# env-init: user local bin (Claude Code, pip --user)\nexport PATH="${HOME}/.local/bin:${PATH}"\n' >> "${ZSHRC}"
fi

# --- 3) Go → /usr/local/go, symlinks in /usr/local/bin ---
# go.dev returns multiple lines (version + build time); only the first line is the release tag.
GO_VER_RAW="$(curl -fsSL 'https://go.dev/VERSION?m=text' | head -n1 | tr -d '\r\n')"
GO_VER="${GO_VER_RAW#go}"
if [[ ! "${GO_VER}" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
  die "unexpected Go version from go.dev (first line): ${GO_VER_RAW}"
fi
GO_TGZ="go${GO_VER}.linux-${GOARCH}.tar.gz"
TMP_GO="/tmp/${GO_TGZ}"
curl -fsSL "https://go.dev/dl/${GO_TGZ}" -o "${TMP_GO}"
$SUDO rm -rf /usr/local/go
$SUDO tar -C /usr/local -xzf "${TMP_GO}"
rm -f "${TMP_GO}"
$SUDO ln -sf /usr/local/go/bin/go /usr/local/bin/go
$SUDO ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt

# --- 4) jq binary → /usr/local/bin ---
case "${GOARCH}" in
  amd64) JQ_ASSET="jq-linux-amd64" ;;
  arm64) JQ_ASSET="jq-linux-arm64" ;;
esac
JQ_TAG="$(
  curl -fsSL -H 'Accept: application/vnd.github+json' -H 'User-Agent: env-init.sh' \
    https://api.github.com/repos/jqlang/jq/releases/latest |
    sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1
)"
if [[ -n "${JQ_TAG}" ]] && curl -fsSL "https://github.com/jqlang/jq/releases/download/${JQ_TAG}/${JQ_ASSET}" -o /tmp/jq.bin; then
  $SUDO install -m 0755 /tmp/jq.bin /usr/local/bin/jq
  rm -f /tmp/jq.bin
else
  log "WARN: jq GitHub download failed; installing distro jq into /usr/local/bin"
  $SUDO apt-get install -y jq
  $SUDO install -m 0755 "$(command -v jq)" /usr/local/bin/jq
  rm -f /tmp/jq.bin
fi

# --- 5) Node.js (for tsc) + TypeScript global → /usr/local/bin ---
if ! command -v node >/dev/null 2>&1; then
  if [[ -n "${SUDO}" ]]; then
    curl -fsSL https://deb.nodesource.com/setup_22.x | $SUDO -E bash -
  else
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  fi
  $SUDO apt-get install -y nodejs
fi
if ! $SUDO npm install -g typescript --prefix /usr/local; then
  log "WARN: global TypeScript (tsc) install failed; retry: sudo npm install -g typescript --prefix /usr/local"
fi

# --- 6) Cursor 3.1 (.deb) ---
CURSOR_DEB="/tmp/cursor-latest.deb"
if curl -fsSL "https://api2.cursor.sh/updates/download/golden/linux-${CURSOR_ARCH}-deb/cursor/3.2" -o "${CURSOR_DEB}"; then
  $SUDO apt-get install -y "${CURSOR_DEB}" 2>/dev/null || $SUDO dpkg -i "${CURSOR_DEB}" 2>/dev/null || \
    log "WARN: Cursor .deb install failed; install from https://cursor.com"
  $SUDO apt-get -f install -y 2>/dev/null || true
else
  log "WARN: Cursor .deb download failed; install from https://cursor.com"
fi
rm -f "${CURSOR_DEB}"

# --- 7) Claude Code CLI (native installer) ---
if ! curl -fsSL https://claude.ai/install.sh | bash; then
  log "WARN: Claude Code CLI install failed; retry: curl -fsSL https://claude.ai/install.sh | bash"
fi

# --- 8) Git global identity ---
git config --global user.email "death0032@gmail.com"
git config --global user.name "marz32one"

# --- 9) golangci-lint (latest, official installer → /usr/local/bin) ---
if curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh | $SUDO sh -s -- -b /usr/local/bin; then
  log "golangci-lint installed: $(/usr/local/bin/golangci-lint --version 2>/dev/null || true)"
else
  log "WARN: golangci-lint install failed; retry: curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh | sh -s -- -b /usr/local/bin"
fi

# Ensure ~/go/bin (GOPATH/bin) is on PATH in zsh so `go install`-ed tools are found
if [[ -f "${ZSHRC}" ]] && ! grep -q 'env-init: go bin' "${ZSHRC}" 2>/dev/null; then
  printf '\n# env-init: go bin (GOPATH)\nexport PATH="${HOME}/go/bin:${PATH}"\n' >> "${ZSHRC}"
fi

# --- 11) Clone otel-traces-test → ~/Document ---
DOC_DIR="${HOME}/Documents"
mkdir -p "${DOC_DIR}"
REPO_DIR="${DOC_DIR}/otel-traces-test"
if [[ ! -d "${REPO_DIR}/.git" ]]; then
  git clone https://github.com/Marz32onE/otel-traces-test.git "${REPO_DIR}"
  if ! git -C "${REPO_DIR}" submodule update --init --recursive; then
    log "WARN: git submodules failed; run: git -C ${REPO_DIR} submodule update --init --recursive"
  fi
else
  log "Repo already exists at ${REPO_DIR}; skipping clone."
fi

# --- 12) RTK (Rust Token Killer) → ~/.local/bin — https://github.com/rtk-ai/rtk#quick-install-linuxmacos
if curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh; then
  log "RTK installed: $(command -v rtk >/dev/null 2>&1 && rtk --version 2>/dev/null || echo 'rtk on PATH after new shell')"
else
  log "WARN: RTK install failed; retry: curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh"
fi

log "Done. Open a new zsh session (or run: exec zsh) and run 'p10k configure' once to finish Powerlevel10k."
log "If zsh is not your login shell yet: chsh -s \"$(command -v zsh)\""
