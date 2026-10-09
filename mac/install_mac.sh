#!/bin/bash
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="$HOME/.local/bin"

echo "=================================================="
echo " Logitech M337 Bluetooth Mouse Switcher Installer"
echo "=================================================="

# 1. Check/Install blueutil
if ! command -v blueutil &> /dev/null; then
    echo "==> blueutil not found. Installing via Homebrew..."
    if command -v brew &> /dev/null; then
        brew install blueutil
    else
        echo "Error: Homebrew is required to install blueutil. Please install brew first."
        exit 1
    fi
else
    echo "✔ blueutil is installed ($(blueutil -v))"
fi

# 2. Build Apps
echo "==> Building macOS Application Bundles..."
"$DIR/build_mac_apps.sh"

# 3. Install App to ~/Applications
USER_APPS="$HOME/Applications"
mkdir -p "$USER_APPS"

echo "==> Installing to $USER_APPS..."
rm -rf "$USER_APPS/Switch Mouse to Mac.app"
cp -R "$DIR/Switch Mouse to Mac.app" "$USER_APPS/"

rm -rf "$USER_APPS/Switch Mouse Menu Bar.app"
cp -R "$DIR/Switch Mouse Menu Bar.app" "$USER_APPS/"

# 4. CLI tool symlink
mkdir -p "$BIN_DIR"
CLI_TARGET="$BIN_DIR/bt-mouse-switch"
ln -sf "$DIR/switch_mouse.py" "$CLI_TARGET"
chmod +x "$CLI_TARGET"

echo ""
echo "=================================================="
echo " Installation Complete!"
echo "=================================================="
echo ""
echo "Ways to use your single-click mouse switcher:"
echo " 1. 🔍 Spotlight / Raycast: Press Cmd+Space and type 'Switch Mouse to Mac'"
echo " 2. 📌 Dock: Drag '$USER_APPS/Switch Mouse to Mac.app' to your Dock"
echo " 3. 🖱️ Menu Bar: Launch '$USER_APPS/Switch Mouse Menu Bar.app' to keep an icon in your menu bar"
echo " 4. 💻 Terminal: Run 'bt-mouse-switch' from anywhere (ensure ~/.local/bin is in PATH)"
echo ""
echo "How switching works:"
echo " 1. Push the Bluetooth button on the bottom of the Logitech M337 (blue light blinks fast)."
echo " 2. Click 'Switch Mouse to Mac'!"
echo " 3. It will automatically forget the old pairing, find the mouse, pair, and connect."
echo ""
