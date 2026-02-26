#!/usr/bin/env bash
# Flutter Linux offscreen rendering setup for CI/headless environments.
#
# Installs Flutter SDK + dependencies for running unit tests and building
# the mascot app on Linux without a display server (using xvfb).
#
# Usage:
#   bash scripts/setup_flutter_linux.sh
#
# After setup:
#   cd mascot && flutter test              # L1: unit tests (no display needed)
#   cd mascot && xvfb-run flutter build linux  # L2: build check (needs xvfb)

set -euo pipefail

FLUTTER_VERSION="3.38.7"
FLUTTER_DIR="${FLUTTER_DIR:-$HOME/flutter}"

echo "=== Flutter Linux Setup ==="

# 1. Install system dependencies
echo "[1/4] Installing system dependencies..."
sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends \
  xvfb \
  libgtk-3-dev \
  clang cmake ninja-build pkg-config \
  libgl1-mesa-dev \
  2>/dev/null

# 2. Install Flutter SDK
if [ -x "$FLUTTER_DIR/bin/flutter" ]; then
  CURRENT_VERSION=$("$FLUTTER_DIR/bin/flutter" --version 2>/dev/null | head -1 | awk '{print $2}')
  echo "[2/4] Flutter $CURRENT_VERSION already installed at $FLUTTER_DIR"
else
  echo "[2/4] Installing Flutter $FLUTTER_VERSION..."
  curl -sL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
    | tar xJ -C "$(dirname "$FLUTTER_DIR")"
  git config --global --add safe.directory "$FLUTTER_DIR"
fi

export PATH="$FLUTTER_DIR/bin:$PATH"

# 3. Enable Linux desktop
echo "[3/4] Enabling Linux desktop target..."
flutter config --enable-linux-desktop 2>/dev/null

# 4. Verify
echo "[4/4] Verifying setup..."
flutter --version
echo ""
echo "=== Setup complete ==="
echo ""
echo "Run tests:  cd mascot && flutter test"
echo "Build:      cd mascot && xvfb-run flutter build linux"
echo ""
echo "Add to PATH: export PATH=\"$FLUTTER_DIR/bin:\$PATH\""
