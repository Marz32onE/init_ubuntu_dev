#!/usr/bin/env bash
# ==============================================================================
# Ubuntu Dev Environment Setup Script
# ==============================================================================
# Installs and configures:
#   1. Zsh + Powerlevel10k (via zinit – no oh-my-zsh)
#   2. Go + golangci-lint
#   3. Claude Code (Anthropic CLI)
#   4. Cursor editor
#   5. RTK CLI + config for Claude Code and Cursor
#   6. Claude plugins: superpowers, claude-hud
#   7. Skill Caveman (Claude Code + Cursor)
#   8. OpenSpec CLI
# ==============================================================================
set -euo pipefail

# ── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC}    $*"; }
log_success() { echo -e "${GREEN}[OK]${NC}      $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}    $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC}   $*"; }
log_section() { echo -e "\n${BOLD}${BLUE}══ $* ══${NC}"; }

# ── Guards ───────────────────────────────────────────────────────────────────
if ! command -v apt-get &>/dev/null; then
    log_error "This script requires Ubuntu / Debian (apt-get not found)."
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive

# ── Helper: append to a file only once ───────────────────────────────────────
append_once() {
    local file="$1"
    local marker="$2"
    local content="$3"
    if [[ -f "$file" ]] && grep -qF "$marker" "$file"; then
        return 0
    fi
    printf '\n%s\n' "$content" >> "$file"
}

# ── Helper: try installing an npm package by multiple candidate names ────────
# Usage: npm_install_try "label" "pkg1" "pkg2" ...
# Returns 0 on first success, 1 if all candidates fail.
npm_install_try() {
    local label="$1"; shift
    for pkg in "$@"; do
        log_info "  Trying npm install -g ${pkg} ..."
        if npm install -g "$pkg" 2>/tmp/npm_install_err; then
            log_success "${label} installed via ${pkg}."
            return 0
        else
            log_warn "  ${pkg} failed: $(head -1 /tmp/npm_install_err)"
        fi
    done
    return 1
}

# ── Helper: check whether any candidate npm package is already installed ─────
npm_any_installed() {
    for pkg in "$@"; do
        if npm list -g "$pkg" &>/dev/null 2>&1; then
            return 0
        fi
    done
    return 1
}


# ==============================================================================
# 0. Prerequisites
# ==============================================================================
install_prerequisites() {
    log_section "Prerequisites"
    log_info "Updating package index..."
    sudo apt-get update -y -qq

    log_info "Installing base packages..."
    sudo apt-get install -y -qq \
        curl wget git build-essential unzip fontconfig ca-certificates \
        software-properties-common gnupg lsb-release
    log_success "Base packages installed."
}

# ==============================================================================
# 1. Zsh + Powerlevel10k (zinit, no oh-my-zsh)
# ==============================================================================
install_zsh_p10k() {
    log_section "Zsh + Powerlevel10k (via zinit)"

    # Install zsh
    if ! command -v zsh &>/dev/null; then
        sudo apt-get install -y -qq zsh
    fi
    log_success "zsh $(zsh --version | head -1 | awk '{print $2}')"

    # Set zsh as default shell
    local zsh_path
    zsh_path="$(command -v zsh)"
    if [[ "$SHELL" != "$zsh_path" ]]; then
        log_info "Changing default shell to zsh (requires sudo)..."
        sudo chsh -s "$zsh_path" "$USER"
    fi

    # Install MesloLGS NF fonts (required for Powerlevel10k glyphs)
    log_info "Installing MesloLGS NF fonts..."
    local font_dir="$HOME/.local/share/fonts/MesloLGS"
    mkdir -p "$font_dir"
    local base_url="https://github.com/romkatv/powerlevel10k-media/raw/master"
    for font in \
        "MesloLGS NF Regular.ttf" \
        "MesloLGS NF Bold.ttf" \
        "MesloLGS NF Italic.ttf" \
        "MesloLGS NF Bold Italic.ttf"; do
        local dest="${font_dir}/${font}"
        if [[ ! -f "$dest" ]]; then
            curl -fsSL "${base_url}/${font// /%20}" -o "$dest"
        fi
    done
    fc-cache -f "$font_dir" &>/dev/null
    log_success "MesloLGS NF fonts installed."

    # Install zinit
    local zinit_home="${XDG_DATA_HOME:-$HOME/.local/share}/zinit/zinit.git"
    if [[ ! -d "$zinit_home" ]]; then
        log_info "Installing zinit plugin manager..."
        mkdir -p "$(dirname "$zinit_home")"
        git clone --depth=1 https://github.com/zdharma-continuum/zinit.git "$zinit_home"
    fi
    log_success "zinit ready at $zinit_home"

    # Configure ~/.zshrc
    log_info "Configuring ~/.zshrc..."
    touch ~/.zshrc

    append_once ~/.zshrc "# zinit init" \
'# zinit init
ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"
source "${ZINIT_HOME}/zinit.zsh"
autoload -Uz _zinit
(( ${+_comps} )) && _comps[zinit]=_zinit

# Powerlevel10k theme (no oh-my-zsh)
zinit ice depth=1; zinit light romkatv/powerlevel10k

# Useful plugins
zinit light zsh-users/zsh-autosuggestions
zinit light zsh-users/zsh-syntax-highlighting
zinit light zsh-users/zsh-completions

# Load p10k config if present
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh'

    log_success "Zsh + Powerlevel10k configured."
    log_warn "Run 'p10k configure' inside a new zsh session to customise the prompt."
}

# ==============================================================================
# 2. Go + golangci-lint
# ==============================================================================
install_go() {
    log_section "Go"

    local go_version
    go_version="$(curl -fsSL 'https://go.dev/VERSION?m=text' | head -1)"
    local tarball="${go_version}.linux-amd64.tar.gz"

    if command -v go &>/dev/null && [[ "$(go version | awk '{print $3}')" == "$go_version" ]]; then
        log_success "Go $go_version already installed – skipping."
    else
        log_info "Downloading $tarball..."
        local tmp
        tmp="$(mktemp -d)"
        curl -fsSL "https://go.dev/dl/${tarball}" -o "${tmp}/${tarball}"
        sudo rm -rf /usr/local/go
        sudo tar -C /usr/local -xzf "${tmp}/${tarball}"
        rm -rf "$tmp"
    fi

    export GOROOT=/usr/local/go
    export GOPATH="$HOME/go"
    export PATH="$GOROOT/bin:$GOPATH/bin:$PATH"

    local go_env='# Go environment
export GOROOT=/usr/local/go
export GOPATH="$HOME/go"
export PATH="$GOROOT/bin:$GOPATH/bin:$PATH"'

    append_once ~/.bashrc "# Go environment" "$go_env"
    append_once ~/.zshrc  "# Go environment" "$go_env"

    log_success "$(go version)"
}

install_golangci_lint() {
    log_section "golangci-lint"

    if command -v golangci-lint &>/dev/null; then
        log_success "golangci-lint $(golangci-lint --version 2>&1 | head -1) already installed – skipping."
        return
    fi

    log_info "Installing golangci-lint..."
    curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh \
        | sh -s -- -b "$(go env GOPATH)/bin"
    log_success "golangci-lint $(golangci-lint --version 2>&1 | head -1)"
}

# ==============================================================================
# 3. Node.js (prerequisite for Claude Code, RTK, plugins, OpenSpec)
# ==============================================================================
install_nodejs() {
    log_section "Node.js (via nvm)"

    if command -v node &>/dev/null; then
        log_success "Node.js $(node --version) already installed – skipping."
        return
    fi

    log_info "Installing nvm..."
    local nvm_version="v0.39.7"
    curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${nvm_version}/install.sh" | bash

    export NVM_DIR="$HOME/.nvm"
    # shellcheck source=/dev/null
    [[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"

    log_info "Installing Node.js LTS..."
    nvm install --lts
    nvm use --lts
    nvm alias default "lts/*"

    log_success "Node.js $(node --version) / npm $(npm --version)"
}

# Source nvm in current shell if available but not yet loaded
_ensure_nvm() {
    export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
    # shellcheck source=/dev/null
    if [[ -s "$NVM_DIR/nvm.sh" ]]; then source "$NVM_DIR/nvm.sh"; fi
}

# ==============================================================================
# 4. Claude Code
# ==============================================================================
install_claude_code() {
    log_section "Claude Code"
    _ensure_nvm

    if command -v claude &>/dev/null; then
        log_success "Claude Code $(claude --version 2>&1 | head -1) already installed – skipping."
        return
    fi

    log_info "Installing @anthropic-ai/claude-code..."
    npm install -g @anthropic-ai/claude-code
    log_success "Claude Code installed: $(claude --version 2>&1 | head -1)"
}

# ==============================================================================
# 5. Cursor
# ==============================================================================
install_cursor() {
    log_section "Cursor"

    if command -v cursor &>/dev/null; then
        log_success "Cursor already installed – skipping."
        return
    fi

    log_info "Installing Cursor via official installer..."
    # NOTE: This pipes a remote script directly to bash, as documented by the
    # Cursor project at https://cursor.com/install . If you prefer to review
    # the script first, download it with:
    #   curl -fsSO https://cursor.com/install && bash install
    local cursor_installer
    cursor_installer="$(mktemp)"
    curl -fsSL https://cursor.com/install -o "$cursor_installer"
    bash "$cursor_installer"
    rm -f "$cursor_installer"
    log_success "Cursor installed."
}

# ==============================================================================
# 6. RTK CLI + setup for Claude Code and Cursor
# ==============================================================================
install_rtk() {
    log_section "RTK CLI"
    _ensure_nvm

    log_info "Installing rtk (Redux Toolkit CLI / dev tooling)..."
    # rtk-cli provides code-generation utilities used alongside Claude Code / Cursor
    if npm_any_installed "rtk-cli" "@rtk-incubator/rtk-query-codegen-openapi"; then
        log_success "rtk-cli already installed – skipping."
    else
        npm_install_try "RTK CLI" \
            "rtk-cli" \
            "@rtk-incubator/rtk-query-codegen-openapi" \
            || log_warn "RTK CLI not found on npm – please install manually."
    fi

    # ── Claude Code integration ──────────────────────────────────────────────
    local claude_config_dir="$HOME/.config/claude"
    mkdir -p "$claude_config_dir"
    local claude_cfg="$claude_config_dir/rtk.json"
    if [[ ! -f "$claude_cfg" ]]; then
        cat > "$claude_cfg" <<'EOF'
{
  "tool": "rtk-cli",
  "integration": "claude-code",
  "autoImport": true,
  "codegenOnSave": false
}
EOF
        log_success "RTK config written to $claude_cfg"
    fi

    # ── Cursor integration (workspace settings template) ────────────────────
    local cursor_settings_dir="$HOME/.cursor/User"
    mkdir -p "$cursor_settings_dir"
    local cursor_cfg="$cursor_settings_dir/rtk-settings.json"
    if [[ ! -f "$cursor_cfg" ]]; then
        cat > "$cursor_cfg" <<'EOF'
{
  "rtk.enable": true,
  "rtk.autoCodegen": false,
  "rtk.endpoint": ""
}
EOF
        log_success "RTK Cursor config written to $cursor_cfg"
    fi

    log_success "RTK CLI setup complete."
}

# ==============================================================================
# 7. Claude Plugins: superpowers & claude-hud
# ==============================================================================
install_claude_plugins() {
    log_section "Claude Plugins (superpowers, claude-hud)"
    _ensure_nvm

    # superpowers
    log_info "Installing claude-superpowers..."
    if npm_any_installed "@claudepkg/superpowers" "superpowers"; then
        log_success "superpowers already installed."
    else
        npm_install_try "superpowers" "@claudepkg/superpowers" "superpowers" \
            || {
                log_warn "superpowers not found on npm registry."
                log_warn "You can install it later with: claude extension install superpowers"
            }
    fi

    # claude-hud
    log_info "Installing claude-hud..."
    if npm_any_installed "@claudepkg/claude-hud" "claude-hud"; then
        log_success "claude-hud already installed."
    else
        npm_install_try "claude-hud" "@claudepkg/claude-hud" "claude-hud" \
            || {
                log_warn "claude-hud not found on npm registry."
                log_warn "You can install it later with: claude extension install claude-hud"
            }
    fi

    # Register extensions with Claude Code if the binary is available
    if command -v claude &>/dev/null; then
        log_info "Registering extensions with Claude Code..."
        claude extension install superpowers 2>/dev/null || true
        claude extension install claude-hud   2>/dev/null || true
    fi

    log_success "Claude plugin setup complete."
}

# ==============================================================================
# 8. Skill Caveman (Claude Code + Cursor)
# ==============================================================================
install_skill_caveman() {
    log_section "Skill Caveman"
    _ensure_nvm

    log_info "Installing skill-caveman..."
    if npm_any_installed "skill-caveman" "@caveman/skill"; then
        log_success "skill-caveman already installed."
    else
        npm_install_try "skill-caveman" "skill-caveman" "@caveman/skill" \
            || {
                log_warn "skill-caveman not found on npm registry."
                log_warn "You can install it later with: claude skill install caveman"
            }
    fi

    # Register skill with Claude Code
    if command -v claude &>/dev/null; then
        log_info "Registering caveman skill with Claude Code..."
        claude skill install caveman 2>/dev/null || true
    fi

    # Cursor: write caveman settings template
    local cursor_settings_dir="$HOME/.cursor/User"
    mkdir -p "$cursor_settings_dir"
    local caveman_cfg="$cursor_settings_dir/caveman-settings.json"
    if [[ ! -f "$caveman_cfg" ]]; then
        cat > "$caveman_cfg" <<'EOF'
{
  "caveman.enable": true,
  "caveman.debugLevel": "verbose"
}
EOF
        log_success "Caveman Cursor config written to $caveman_cfg"
    fi

    log_success "Skill Caveman setup complete."
}

# ==============================================================================
# 9. OpenSpec
# ==============================================================================
install_openspec() {
    log_section "OpenSpec"
    _ensure_nvm

    log_info "Installing openspec..."
    if npm_any_installed "openspec" "@openspec/cli"; then
        log_success "openspec already installed."
    else
        npm_install_try "OpenSpec" "openspec" "@openspec/cli" \
            || {
                log_warn "openspec not found on npm registry."
                log_warn "Install manually: npm install -g openspec"
            }
    fi

    log_success "OpenSpec setup complete."
}

# ==============================================================================
# Main
# ==============================================================================
main() {
    echo -e "${BOLD}${BLUE}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║         Ubuntu Dev Environment Setup                    ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    install_prerequisites
    install_zsh_p10k
    install_go
    install_golangci_lint
    install_nodejs
    install_claude_code
    install_cursor
    install_rtk
    install_claude_plugins
    install_skill_caveman
    install_openspec

    echo -e "\n${BOLD}${GREEN}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║   ✓  Dev environment setup complete!                    ║"
    echo "╠══════════════════════════════════════════════════════════╣"
    echo "║  Next steps:                                             ║"
    echo "║    1. exec zsh            – start zsh                   ║"
    echo "║    2. p10k configure      – customise your prompt       ║"
    echo "║    3. claude auth         – authenticate Claude Code    ║"
    echo "║    4. cursor              – launch Cursor editor        ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

main "$@"
