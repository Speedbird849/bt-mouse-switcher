#!/bin/bash
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="$HOME/.local/bin"

echo "=================================================="
echo " Logitech M336/M337/M535 Mouse Switcher Installer"
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
    echo "blueutil is installed ($(blueutil -v))"
fi

# 2. Build Apps
echo "==> Building macOS Application Bundles..."
"$DIR/build_mac_apps.sh"

# 3. Install App to /Applications (or fallback to ~/Applications)
APP_DIR="/Applications"
if [ ! -w "$APP_DIR" ]; then
    APP_DIR="$HOME/Applications"
fi
mkdir -p "$APP_DIR"

echo "==> Installing to $APP_DIR..."
rm -rf "$APP_DIR/Switch Mouse to Mac.app"
cp -R "$DIR/Switch Mouse to Mac.app" "$APP_DIR/"

rm -rf "$APP_DIR/Switch Mouse Menu Bar.app"
cp -R "$DIR/Switch Mouse Menu Bar.app" "$APP_DIR/"

# 4. CLI tool symlink
mkdir -p "$BIN_DIR"
CLI_TARGET="$BIN_DIR/bt-mouse-switch"
ln -sf "$DIR/switch_mouse.py" "$CLI_TARGET"
chmod +x "$CLI_TARGET"

echo ""
echo "=================================================="
echo " Installation Complete"
echo "=================================================="
echo ""
echo "Ways to use your single-click mouse switcher:"
echo " 1. Spotlight / Raycast: Press Cmd+Space and type 'Switch Mouse to Mac'"
echo " 2. Dock: Drag '$APP_DIR/Switch Mouse to Mac.app' to your Dock"
echo " 3. Menu Bar: Launch '$APP_DIR/Switch Mouse Menu Bar.app'"
echo " 4. Terminal: Run 'bt-mouse-switch' from anywhere (ensure ~/.local/bin is in PATH)"
echo ""
echo "How switching works:"
echo " 1. Push the Bluetooth button on the bottom of the Logitech mouse (blue light blinks fast)."
echo " 2. Click 'Switch Mouse to Mac'."
echo " 3. It will automatically forget the old pairing, find the mouse, pair, and connect."
echo ""
