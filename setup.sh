#!/usr/bin/env bash
# ==============================================================================
# Ubuntu Dev Environment Setup Script
# ==============================================================================
# Installs and configures:
#   1.  Zsh + Powerlevel10k (direct clone – no zinit/oh-my-zsh)
#   2.  jq
#   3.  Go + golangci-lint
#   4.  Node.js (nvm) + TypeScript
#   5.  Claude Code (native installer)
#   6.  Cursor editor
#   7.  RTK (Rust Token Killer)
#   8.  Claude plugins: superpowers, claude-hud, claude-code-setup
#   9.  Skill Caveman
#   10. OpenSpec CLI
#   11. Git global identity + otel-traces-test repo clone
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
    local err_file
    err_file="$(mktemp)"
    for pkg in "$@"; do
        log_info "  Trying npm install -g ${pkg} ..."
        if npm install -g "$pkg" 2>"$err_file"; then
            rm -f "$err_file"
            log_success "${label} installed via ${pkg}."
            return 0
        else
            log_warn "  ${pkg} failed: $(head -1 "$err_file")"
        fi
    done
    rm -f "$err_file"
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
# 1. Zsh + Powerlevel10k (direct clone, no zinit/oh-my-zsh)
# ==============================================================================
install_zsh_p10k() {
    log_section "Zsh + Powerlevel10k"

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
        if ! sudo chsh -s "$zsh_path" "$USER"; then
            log_warn "Could not change default shell. Run manually: sudo chsh -s $zsh_path $USER"
        fi
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

    # Clone plugins directly
    local plugins_dir="$HOME/.config/zsh/plugins"
    mkdir -p "$plugins_dir"

    if [[ ! -d "$plugins_dir/powerlevel10k" ]]; then
        git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$plugins_dir/powerlevel10k"
    fi
    if [[ ! -d "$plugins_dir/zsh-autosuggestions" ]]; then
        git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions "$plugins_dir/zsh-autosuggestions"
    fi
    if [[ ! -d "$plugins_dir/zsh-syntax-highlighting" ]]; then
        git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting "$plugins_dir/zsh-syntax-highlighting"
    fi
    log_success "Zsh plugins cloned to $plugins_dir"

    # Configure ~/.zshrc
    touch ~/.zshrc

    # Powerlevel10k instant prompt must be first — prepend to existing content
    if ! grep -q 'p10k-instant-prompt' ~/.zshrc; then
        local tmp
        tmp="$(mktemp)"
        cat > "$tmp" <<'ZSHINSTANT'
# Enable Powerlevel10k instant prompt (quiet mode)
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

ZSHINSTANT
        cat ~/.zshrc >> "$tmp"
        mv "$tmp" ~/.zshrc
    fi

    # Source plugins (idempotent via marker)
    append_once ~/.zshrc "# env-init: zsh plugins" \
'# env-init: zsh plugins
source "$HOME/.config/zsh/plugins/powerlevel10k/powerlevel10k.zsh-theme"
source "$HOME/.config/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh"
source "$HOME/.config/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh'

    # ~/.local/bin on PATH (Claude Code native installer targets this dir)
    mkdir -p "$HOME/.local/bin"
    append_once ~/.zshrc "# env-init: user local bin" \
'# env-init: user local bin (Claude Code, pip --user)
export PATH="${HOME}/.local/bin:${PATH}"'

    log_success "Zsh + Powerlevel10k configured."
    log_warn "Run 'p10k configure' inside a new zsh session to customise the prompt."
}

# ==============================================================================
# 2. jq
# ==============================================================================
install_jq() {
    log_section "jq"

    local goarch
    case "$(uname -m)" in
        x86_64)        goarch="amd64" ;;
        aarch64|arm64) goarch="arm64" ;;
        *) log_error "Unsupported architecture: $(uname -m)"; exit 1 ;;
    esac

    if command -v jq &>/dev/null; then
        log_success "jq $(jq --version) already installed – skipping."
        return
    fi

    local jq_asset="jq-linux-${goarch}"
    local jq_tag
    jq_tag="$(curl -fsSL -H 'Accept: application/vnd.github+json' -H 'User-Agent: setup.sh' \
        https://api.github.com/repos/jqlang/jq/releases/latest \
        | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)"

    if [[ -n "$jq_tag" ]] && curl -fsSL \
        "https://github.com/jqlang/jq/releases/download/${jq_tag}/${jq_asset}" -o /tmp/jq.bin; then
        sudo install -m 0755 /tmp/jq.bin /usr/local/bin/jq
        rm -f /tmp/jq.bin
    else
        log_warn "jq GitHub download failed; installing distro jq"
        sudo apt-get install -y -qq jq
        sudo install -m 0755 "$(command -v jq)" /usr/local/bin/jq
    fi
    log_success "jq $(jq --version)"
}

# ==============================================================================
# 3. Go + golangci-lint
# ==============================================================================
install_go() {
    log_section "Go"

    local goarch
    case "$(uname -m)" in
        x86_64)        goarch="amd64" ;;
        aarch64|arm64) goarch="arm64" ;;
        *) log_error "Unsupported architecture: $(uname -m)"; exit 1 ;;
    esac

    local go_version
    go_version="$(curl -fsSL 'https://go.dev/VERSION?m=text' | head -1 | tr -d '\r\n')" || go_version=""
    if [[ -z "$go_version" ]]; then
        log_warn "Could not fetch latest Go version – skipping version check."
    fi
    local tarball="${go_version}.linux-${goarch}.tar.gz"

    if [[ -n "$go_version" ]] && command -v go &>/dev/null && [[ "$(go version | awk '{print $3}')" == "$go_version" ]]; then
        log_success "Go $go_version already installed – skipping."
    else
        log_info "Downloading $tarball..."
        local tmp
        tmp="$(mktemp -d)"
        curl -fsSL "https://go.dev/dl/${tarball}" -o "${tmp}/${tarball}"
        sudo rm -rf /usr/local/go
        sudo tar -C /usr/local -xzf "${tmp}/${tarball}"
        rm -rf "$tmp"
        sudo ln -sf /usr/local/go/bin/go    /usr/local/bin/go
        sudo ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt
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
        | sudo sh -s -- -b /usr/local/bin
    log_success "golangci-lint $(golangci-lint --version 2>&1 | head -1)"
}

# ==============================================================================
# 4. Node.js (prerequisite for Claude Code, RTK, plugins, OpenSpec) + TypeScript
# ==============================================================================
install_nodejs() {
    log_section "Node.js (via nvm) + TypeScript"

    local nvm_version="v0.39.7"
    if [[ ! -s "$HOME/.nvm/nvm.sh" ]]; then
        log_info "Installing nvm..."
        curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${nvm_version}/install.sh" | bash
    else
        log_success "nvm already installed – skipping."
    fi

    export NVM_DIR="$HOME/.nvm"
    # shellcheck source=/dev/null
    [[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"

    if ! command -v nvm &>/dev/null; then
        log_error "nvm installation failed. Install manually: https://github.com/nvm-sh/nvm"
        exit 1
    fi

    if ! command -v node &>/dev/null; then
        log_info "Installing Node.js LTS..."
        nvm install --lts
        nvm use --lts
        nvm alias default "lts/*"
    fi
    log_success "Node.js $(node --version) / npm $(npm --version)"

    if ! command -v tsc &>/dev/null; then
        log_info "Installing TypeScript (tsc)..."
        npm install -g typescript || log_warn "TypeScript install failed. Retry: npm install -g typescript"
    fi
    log_success "TypeScript $(tsc --version 2>/dev/null)"
}

# Source nvm in current shell if available but not yet loaded
_ensure_nvm() {
    export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
    # shellcheck source=/dev/null
    if [[ -s "$NVM_DIR/nvm.sh" ]]; then source "$NVM_DIR/nvm.sh"; fi
}

# ==============================================================================
# 5. Claude Code
# ==============================================================================
install_claude_code() {
    log_section "Claude Code"

    if command -v claude &>/dev/null; then
        log_success "Claude Code $(claude --version 2>&1 | head -1) already installed – skipping."
        return
    fi

    log_info "Installing Claude Code via native installer..."
    if ! curl -fsSL https://claude.ai/install.sh | bash; then
        log_warn "Claude Code install failed. Retry: curl -fsSL https://claude.ai/install.sh | bash"
        return
    fi
    export PATH="$HOME/.local/bin:$PATH"
    if command -v claude &>/dev/null; then
        log_success "Claude Code installed: $(claude --version 2>&1 | head -1)"
    else
        log_warn "Claude Code installed but 'claude' not yet on PATH – open a new shell."
    fi
}

# ==============================================================================
# 6. Cursor
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
# 7. RTK (Rust Token Killer)
# ==============================================================================
install_rtk() {
    log_section "RTK (Rust Token Killer)"

    if command -v rtk &>/dev/null; then
        log_success "RTK $(rtk --version 2>/dev/null) already installed – skipping."
        return
    fi

    log_info "Installing RTK (Rust Token Killer) → ~/.local/bin..."
    if curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh; then
        export PATH="$HOME/.local/bin:$PATH"
        log_success "RTK installed: $(command -v rtk &>/dev/null && rtk --version 2>/dev/null || echo 'available after new shell')"
    else
        log_warn "RTK install failed. Retry: curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh"
    fi
}

# ==============================================================================
# 8. Claude Plugins: superpowers, claude-hud & claude-code-setup
# ==============================================================================
install_claude_plugins() {
    log_section "Claude Plugins (superpowers, claude-hud, claude-code-setup)"

    if ! command -v claude &>/dev/null; then
        log_warn "Claude Code not found – skipping plugin installation."
        return
    fi

    log_info "Installing superpowers..."
    claude plugin install superpowers@claude-plugins-official \
        || log_warn "superpowers install failed. Retry: claude plugin install superpowers@claude-plugins-official"

    log_info "Installing claude-code-setup..."
    claude plugin install claude-code-setup@claude-plugins-official \
        || log_warn "claude-code-setup install failed. Retry: claude plugin install claude-code-setup@claude-plugins-official"

    log_info "Installing claude-hud..."
    claude plugin marketplace add jarrodwatts/claude-hud \
        && claude plugin install claude-hud \
        || log_warn "claude-hud install failed. Retry: claude plugin marketplace add jarrodwatts/claude-hud && claude plugin install claude-hud"

    log_success "Claude plugin setup complete."
}

# ==============================================================================
# 9. Skill Caveman (Claude Code + Cursor)
# ==============================================================================
install_skill_caveman() {
    log_section "Skill Caveman"

    if ! command -v claude &>/dev/null; then
        log_warn "Claude Code not found – skipping caveman install."
        return
    fi

    log_info "Installing caveman plugin..."
    claude plugin marketplace add JuliusBrussee/caveman \
        && claude plugin install caveman@caveman \
        || log_warn "caveman install failed. Retry: claude plugin marketplace add JuliusBrussee/caveman && claude plugin install caveman@caveman"

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
# 10. OpenSpec
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
# 11. Git global identity
# ==============================================================================
install_git_config() {
    log_section "Git global config"
    git config --global user.email "death0032@gmail.com"
    git config --global user.name "marz32one"
    log_success "Git identity: marz32one <death0032@gmail.com>"
}

# ==============================================================================
# 12. Clone otel-traces-test
# ==============================================================================
install_repo() {
    log_section "otel-traces-test repo"

    local repo_dir="$HOME/Documents/otel-traces-test"
    mkdir -p "$HOME/Documents"

    if [[ -d "$repo_dir/.git" ]]; then
        log_success "Repo already exists at $repo_dir – skipping."
        return
    fi

    git clone https://github.com/Marz32onE/otel-traces-test.git "$repo_dir"
    if ! git -C "$repo_dir" submodule update --init --recursive; then
        log_warn "Submodules failed. Run: git -C $repo_dir submodule update --init --recursive"
    fi
    log_success "otel-traces-test cloned to $repo_dir"
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
    install_jq
    install_go
    install_golangci_lint
    install_nodejs
    install_claude_code
    install_cursor
    install_rtk
    install_claude_plugins
    install_skill_caveman
    install_openspec
    install_git_config
    install_repo

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
