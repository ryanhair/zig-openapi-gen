#!/bin/bash
set -e

# Configuration
REPO="ryanhair/zig-openapi-gen"
INSTALL_DIR="$HOME/.local/bin"
BINARY_NAME="openapi-gen"

# Detect OS and Arch
OS="$(uname -s)"
ARCH="$(uname -m)"

case "$OS" in
    Linux)
        OS_TYPE="linux"
        ;;
    Darwin)
        OS_TYPE="macos"
        ;;
    MINGW*|CYGWIN*|MSYS*)
        OS_TYPE="windows"
        ;;
    *)
        echo "Unsupported OS: $OS"
        exit 1
        ;;
esac

case "$ARCH" in
    x86_64)
        ARCH_TYPE="x86_64"
        ;;
    aarch64|arm64)
        ARCH_TYPE="aarch64"
        ;;
    *)
        echo "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

TARGET="${ARCH_TYPE}-${OS_TYPE}"
echo "Detected target: $TARGET"

# Determine Version
if [ -z "$1" ]; then
    echo "Fetching latest version..."
    LATEST_RELEASE_URL="https://api.github.com/repos/$REPO/releases/latest"
    VERSION=$(curl -s $LATEST_RELEASE_URL | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    if [ -z "$VERSION" ]; then
        echo "Error: Could not find latest release. Please specify a version."
        exit 1
    fi
else
    VERSION="$1"
fi

echo "Installing $BINARY_NAME $VERSION..."

# Download
FILENAME="${BINARY_NAME}-${TARGET}.tar.gz"
if [ "$OS_TYPE" == "windows" ]; then
    FILENAME="${BINARY_NAME}-${TARGET}.zip"
fi

DOWNLOAD_URL="https://github.com/$REPO/releases/download/$VERSION/$FILENAME"
echo "Downloading $DOWNLOAD_URL..."

TMP_DIR=$(mktemp -d)
curl -L -o "$TMP_DIR/$FILENAME" "$DOWNLOAD_URL"

# Extract and Install
echo "Extracting..."
if [ "$OS_TYPE" == "windows" ]; then
    unzip -q "$TMP_DIR/$FILENAME" -d "$TMP_DIR"
else
    tar -xzf "$TMP_DIR/$FILENAME" -C "$TMP_DIR"
fi

# Ensure install directory exists
mkdir -p "$INSTALL_DIR"

# Move binary
echo "Installing to $INSTALL_DIR..."
if [ "$OS_TYPE" == "windows" ]; then
    mv "$TMP_DIR/$BINARY_NAME.exe" "$INSTALL_DIR/$BINARY_NAME.exe"
else
    mv "$TMP_DIR/$BINARY_NAME" "$INSTALL_DIR/$BINARY_NAME"
    chmod +x "$INSTALL_DIR/$BINARY_NAME"
fi

# Cleanup
rm -rf "$TMP_DIR"

echo "Success! $BINARY_NAME installed to $INSTALL_DIR"
echo "Make sure $INSTALL_DIR is in your PATH."
