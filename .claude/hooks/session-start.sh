#!/bin/bash
set -euo pipefail

# Only run in remote (web) environments
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

SWIFT_VERSION="6.2.3"
SWIFTLINT_VERSION="0.63.2"
SWIFT_DIR="$HOME/.swift"
INSTALL_DIR="$HOME/.local/bin"

# Check if all tools are already set up
if command -v swift &>/dev/null && command -v swiftlint &>/dev/null \
  && swiftlint version 2>/dev/null | grep -q "$SWIFTLINT_VERSION" \
  && command -v rune &>/dev/null; then
  exit 0
fi

# Detect architecture
ARCH=$(uname -m)
case "$ARCH" in
  x86_64)  ARCH_SUFFIX="amd64" ;;
  aarch64) ARCH_SUFFIX="arm64" ;;
  arm64)   ARCH_SUFFIX="arm64" ;;
  *)
    echo "Unsupported architecture: $ARCH" >&2
    exit 1
    ;;
esac

mkdir -p "$INSTALL_DIR"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Install Swift toolchain (required for SwiftLint's SourceKit dependency)
if ! command -v swift &>/dev/null; then
  UBUNTU_VERSION=$(. /etc/os-release && echo "$VERSION_ID")
  UBUNTU_SUFFIX="${UBUNTU_VERSION//.}"
  SWIFT_URL="https://download.swift.org/swift-${SWIFT_VERSION}-release/ubuntu${UBUNTU_SUFFIX}/swift-${SWIFT_VERSION}-RELEASE/swift-${SWIFT_VERSION}-RELEASE-ubuntu${UBUNTU_VERSION}.tar.gz"

  echo "Installing Swift ${SWIFT_VERSION}..."
  curl -fsSL "$SWIFT_URL" -o "$TMPDIR/swift.tar.gz"
  mkdir -p "$SWIFT_DIR"
  tar xzf "$TMPDIR/swift.tar.gz" -C "$SWIFT_DIR" --strip-components=1

  # Persist Swift paths for the session
  if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
    echo "export PATH=\"$SWIFT_DIR/usr/bin:\$PATH\"" >> "$CLAUDE_ENV_FILE"
    echo "export LD_LIBRARY_PATH=\"$SWIFT_DIR/usr/lib/swift/linux:\${LD_LIBRARY_PATH:-}\"" >> "$CLAUDE_ENV_FILE"
  fi
  export PATH="$SWIFT_DIR/usr/bin:$PATH"
  export LD_LIBRARY_PATH="$SWIFT_DIR/usr/lib/swift/linux:${LD_LIBRARY_PATH:-}"

  echo "Swift $(swift --version 2>&1 | head -1) installed."
fi

# Install SwiftLint
if ! command -v swiftlint &>/dev/null || ! swiftlint version 2>/dev/null | grep -q "$SWIFTLINT_VERSION"; then
  SWIFTLINT_URL="https://github.com/realm/SwiftLint/releases/download/${SWIFTLINT_VERSION}/swiftlint_linux_${ARCH_SUFFIX}.zip"

  echo "Installing SwiftLint ${SWIFTLINT_VERSION} (${ARCH_SUFFIX})..."
  curl -fsSL "$SWIFTLINT_URL" -o "$TMPDIR/swiftlint.zip"
  unzip -qo "$TMPDIR/swiftlint.zip" -d "$TMPDIR/swiftlint"
  install -m 755 "$TMPDIR/swiftlint/swiftlint" "$INSTALL_DIR/swiftlint"

  echo "SwiftLint $(swiftlint version) installed."
fi

# Install Rune (latest release)
if ! command -v rune &>/dev/null; then
  RUNE_TAG=$(curl -fsSL "https://api.github.com/repos/ArjenSchwarz/rune/releases/latest" | grep '"tag_name"' | sed 's/.*"tag_name": *"//;s/".*//')
  RUNE_VERSION="${RUNE_TAG#v}"
  RUNE_URL="https://github.com/ArjenSchwarz/rune/releases/download/${RUNE_TAG}/rune-${RUNE_TAG}-linux-${ARCH_SUFFIX}.tar.gz"

  echo "Installing Rune ${RUNE_VERSION} (${ARCH_SUFFIX})..."
  curl -fsSL "$RUNE_URL" -o "$TMPDIR/rune.tar.gz"
  tar xzf "$TMPDIR/rune.tar.gz" -C "$TMPDIR"
  install -m 755 "$TMPDIR/rune" "$INSTALL_DIR/rune"

  echo "Rune ${RUNE_VERSION} installed."
fi

# Ensure install dir is on PATH
if ! echo "$PATH" | tr ':' '\n' | grep -q "^$INSTALL_DIR$"; then
  if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
    echo "export PATH=\"$INSTALL_DIR:\$PATH\"" >> "$CLAUDE_ENV_FILE"
  fi
  export PATH="$INSTALL_DIR:$PATH"
fi

echo "Session hook complete."
