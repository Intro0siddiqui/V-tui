#!/bin/bash
# Build and install vtui globally
# Usage: ./build-install.sh

set -e  # Exit on error

PROJECT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BINARY_NAME="vtui"
GLOBAL_BIN="/usr/local/bin/${BINARY_NAME}"
TEMP_BINARY="${PROJECT_DIR}/zig-out/bin/${BINARY_NAME}"

echo "=== Building vtui ==="
cd "${PROJECT_DIR}"
zig build -Drelease=true

if [ ! -f "${TEMP_BINARY}" ]; then
    echo "Error: Binary not found at ${TEMP_BINARY}"
    exit 1
fi

echo ""
echo "=== Binary built successfully ==="
echo "Location: ${TEMP_BINARY}"
echo ""

# Check if running with sudo
if [ "$EUID" -eq 0 ]; then
    echo "Installing globally..."
    rm -f "${GLOBAL_BIN}"
    cp "${TEMP_BINARY}" "${GLOBAL_BIN}"
    chmod +x "${GLOBAL_BIN}"
    echo "✓ vtui installed to ${GLOBAL_BIN}"
else
    echo "To install globally, run:"
    echo "  sudo ./build-install.sh"
    echo ""
    echo "Or manually:"
    echo "  sudo rm -f ${GLOBAL_BIN}"
    echo "  sudo cp ${TEMP_BINARY} ${GLOBAL_BIN}"
    echo "  sudo chmod +x ${GLOBAL_BIN}"
fi

echo ""
echo "Usage:"
echo "  vtui --help       # Show help"
echo "  vtui --demo       # Run demo mode"
echo "  vtui htop         # Run htop in PTY"
