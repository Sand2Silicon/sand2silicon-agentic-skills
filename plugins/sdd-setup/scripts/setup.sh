#!/usr/bin/env bash
# setup.sh — Runs INSIDE the container after creation.
# Called via devcontainer.json "postCreateCommand".
#
# Purpose:
#   Install user-space development tools that aren't baked into the Dockerfile.
#   These install to ~/.local/bin (Claude, dolt, bd) or ~/.npm-global (openspec)
#   so they work as a non-root container user.
#
# Usage:
#   ./setup.sh [--claude] [--beads] [--openspec] [--all]
#
# Each flag installs/configures the named tool. --all enables everything.
# With no flags, only basic environment setup is performed.
#
# NOTE: uv is installed system-wide in the Dockerfile (UV_INSTALL_DIR=/usr/local/bin).
# It is NOT installed by this script to avoid duplication.
#
# Versions are pinned here — bump manually when upgrading.
#
set -euo pipefail

# --- Pinned versions ---
DOLT_VERSION="${DOLT_VERSION:-1.83.6}"
BD_VERSION="${BD_VERSION:-0.62.0}"
OPENSPEC_VERSION="${OPENSPEC_VERSION:-1.2.0}"

# --- Feature flags ---
INSTALL_CLAUDE=false
INSTALL_BEADS=false
INSTALL_OPENSPEC=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --claude)   INSTALL_CLAUDE=true; shift ;;
    --beads)    INSTALL_BEADS=true; shift ;;
    --openspec) INSTALL_OPENSPEC=true; shift ;;
    --all)      INSTALL_CLAUDE=true; INSTALL_BEADS=true; INSTALL_OPENSPEC=true; shift ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

echo "=== Devcontainer setup ==="
echo "Claude: $INSTALL_CLAUDE | Beads: $INSTALL_BEADS | OpenSpec: $INSTALL_OPENSPEC"
echo ""

# --- Ensure ~/.local/bin exists and is on PATH ---
mkdir -p "$HOME/.local/bin"
export PATH="$HOME/.local/bin:$PATH"

# --- Helper: check if command exists ---
has() { command -v "$1" &>/dev/null; }

# =========================================================================
# 1. Claude Code CLI
# =========================================================================
if [[ "$INSTALL_CLAUDE" == "true" ]]; then
  echo "[claude] Installing Claude Code CLI..."
  if has claude; then
    echo "  Already installed: $(claude --version 2>/dev/null || echo 'unknown version')"
  else
    curl -fsSL https://claude.ai/install.sh | bash || echo 'WARNING: Claude Code install failed - continuing'
    echo "  Installed: $(claude --version 2>/dev/null || echo 'check manually')"
  fi
  # Ensure PATH persistence in .bashrc
  if ! grep -q '\.local/bin' "$HOME/.bashrc" 2>/dev/null; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
    echo "  Added ~/.local/bin to .bashrc PATH"
  fi
  echo ""
fi

# =========================================================================
# 2. OpenSpec (requires Node.js + npm in the Dockerfile)
# =========================================================================
if [[ "$INSTALL_OPENSPEC" == "true" ]]; then
  echo "[openspec] Installing OpenSpec v${OPENSPEC_VERSION}..."

  if ! has npm; then
    echo "  ERROR: npm not found. Node.js must be installed in the Dockerfile first."
    echo "  See the add-openspec-to-project skill for Dockerfile instructions."
  elif has openspec; then
    echo "  Already installed: $(openspec --version 2>/dev/null || echo 'available')"
  else
    # Configure npm to install global packages in a user-writable directory.
    # This avoids EACCES errors when running as non-root user.
    mkdir -p "$HOME/.npm-global"
    npm config set prefix "$HOME/.npm-global"
    export PATH="$HOME/.npm-global/bin:$PATH"
    if ! grep -q '\.npm-global/bin' "$HOME/.bashrc" 2>/dev/null; then
      echo 'export PATH="$HOME/.npm-global/bin:$PATH"' >> "$HOME/.bashrc"
    fi

    npm install -g @fission-ai/openspec@${OPENSPEC_VERSION}
    echo "  Installed: openspec@${OPENSPEC_VERSION}"
  fi
  echo ""
fi

# =========================================================================
# 3. Dolt (database backend for Beads)
# =========================================================================
if [[ "$INSTALL_BEADS" == "true" ]]; then
  echo "[dolt] Installing Dolt v${DOLT_VERSION}..."
  if has dolt; then
    echo "  Already installed: $(dolt version 2>/dev/null | head -1 || echo 'available')"
  else
    # Direct tarball download to ~/.local/bin (user-space, no root needed)
    curl -fsSL "https://github.com/dolthub/dolt/releases/download/v${DOLT_VERSION}/dolt-linux-amd64.tar.gz" -o /tmp/dolt.tar.gz \
        && tar -xzf /tmp/dolt.tar.gz -C /tmp \
        && cp /tmp/dolt-linux-amd64/bin/dolt "$HOME/.local/bin/" \
        && rm -rf /tmp/dolt.tar.gz /tmp/dolt-linux-amd64
    echo "  Installed: dolt v${DOLT_VERSION} to ~/.local/bin/"
  fi
  echo ""

  # --- Beads (bd CLI) ---
  echo "[beads] Installing Beads v${BD_VERSION}..."
  if has bd; then
    echo "  Already installed: $(bd --version 2>/dev/null || echo 'available')"
  else
    # Direct binary download — do NOT use upstream install.sh in Docker
    # (known bug: ANSI escape codes in detect_platform() corrupt the download URL)
    curl -fsSL "https://github.com/steveyegge/beads/releases/download/v${BD_VERSION}/beads_${BD_VERSION}_linux_amd64.tar.gz" -o /tmp/beads.tar.gz \
        && tar -xzf /tmp/beads.tar.gz -C "$HOME/.local/bin" bd \
        && rm /tmp/beads.tar.gz
    echo "  Installed: bd v${BD_VERSION} to ~/.local/bin/"
  fi
  echo ""
fi

# =========================================================================
# 4. Fix executable permissions (lost on container rebuild)
# =========================================================================
echo "[permissions] Fixing executable bits on scripts and hooks..."
find .devcontainer -name '*.sh' -exec chmod +x {} \; 2>/dev/null || true
if [[ -d ".beads/hooks" ]]; then
  find .beads/hooks -type f -exec chmod +x {} \; 2>/dev/null || true
fi
find scripts -name '*.sh' -exec chmod +x {} \; 2>/dev/null || true
echo "  Done."
echo ""

# =========================================================================
# 5. Git safe directory (bind-mounted repos trigger ownership check)
# =========================================================================
echo "[git] Configuring git safe directories..."
WORKSPACE="$(pwd)"
git config --global --add safe.directory "$WORKSPACE" 2>/dev/null || true
echo "  Added $WORKSPACE as safe directory."
echo ""

echo "=== Setup complete ==="
