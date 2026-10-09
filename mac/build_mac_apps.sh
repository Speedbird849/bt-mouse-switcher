#!/bin/bash
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$DIR/build"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> 1. Generating App Icon..."
if [ ! -f /tmp/BTMouseIcon.icns ]; then
python3 - << 'EOF'
import Cocoa, os, subprocess
from Foundation import NSMakeSize, NSMakeRect, NSZeroRect

iconset_dir = '/tmp/BTMouseIcon.iconset'
os.makedirs(iconset_dir, exist_ok=True)

sizes = [16, 32, 64, 128, 256, 512]
for s in sizes:
    for scale in [1, 2]:
        px = s * scale
        name = f"icon_{s}x{s}.png" if scale == 1 else f"icon_{s}x{s}@2x.png"
        img = Cocoa.NSImage.alloc().initWithSize_(NSMakeSize(px, px))
        img.lockFocus()
        
        # Background gradient or smooth rounded rect
        bg = Cocoa.NSColor.colorWithCalibratedRed_green_blue_alpha_(0.12, 0.48, 0.90, 1.0)
        bg.setFill()
        path = Cocoa.NSBezierPath.bezierPathWithRoundedRect_xRadius_yRadius_(
            Cocoa.NSMakeRect(0, 0, px, px), px * 0.22, px * 0.22
        )
        path.fill()
        
        # SF Symbol computermouse.fill
        sym = Cocoa.NSImage.imageWithSystemSymbolName_accessibilityDescription_('computermouse.fill', None)
        if sym:
            sym_config = Cocoa.NSImageSymbolConfiguration.configurationWithPointSize_weight_(px * 0.55, 5)
            sym = sym.imageWithSymbolConfiguration_(sym_config)
            Cocoa.NSColor.whiteColor().set()
            rect = Cocoa.NSMakeRect(px * 0.225, px * 0.225, px * 0.55, px * 0.55)
            sym.drawInRect_fromRect_operation_fraction_(
                rect, Cocoa.NSZeroRect, Cocoa.NSCompositingOperationSourceOver, 1.0
            )
            
        img.unlockFocus()
        
        tiff = img.TIFFRepresentation()
        bitmap = Cocoa.NSBitmapImageRep.imageRepWithData_(tiff)
        png = bitmap.representationUsingType_properties_(Cocoa.NSPNGFileType, {})
        png.writeToFile_atomically_(os.path.join(iconset_dir, name), True)

subprocess.run(['iconutil', '-c', 'icns', iconset_dir, '-o', '/tmp/BTMouseIcon.icns'], check=True)
EOF
fi

ICNS_FILE="/tmp/BTMouseIcon.icns"

echo "==> 2. Building 'Switch Mouse to Mac.app' (One-Click Launcher)..."
LAUNCHER_APP="$DIR/Switch Mouse to Mac.app"
rm -rf "$LAUNCHER_APP"
mkdir -p "$LAUNCHER_APP/Contents/MacOS"
mkdir -p "$LAUNCHER_APP/Contents/Resources"

cp "$ICNS_FILE" "$LAUNCHER_APP/Contents/Resources/AppIcon.icns"
cp "$DIR/switch_mouse.py" "$LAUNCHER_APP/Contents/Resources/switch_mouse.py"
chmod +x "$LAUNCHER_APP/Contents/Resources/switch_mouse.py"

cat << 'EOF' > "$LAUNCHER_APP/Contents/MacOS/Switch Mouse"
#!/bin/bash
DIR="$(cd "$(dirname "$0")" && pwd)"
RESOURCES="$DIR/../Resources"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
OUTPUT=$(/usr/bin/python3 "$RESOURCES/switch_mouse.py" "$@" 2>&1)
EXIT_CODE=$?
if [ $EXIT_CODE -ne 0 ]; then
    ESCAPED_OUTPUT=$(echo "$OUTPUT" | sed 's/"/\\"/g')
    osascript -e "display alert \"Mouse Switch Failed\" message \"$ESCAPED_OUTPUT\n\nMake sure the pairing button underneath the mouse is blinking rapidly and try again.\""
fi
exit $EXIT_CODE
EOF
chmod +x "$LAUNCHER_APP/Contents/MacOS/Switch Mouse"

cat << 'EOF' > "$LAUNCHER_APP/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Switch Mouse</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.btmouseswitcher.mac</string>
    <key>CFBundleName</key>
    <string>Switch Mouse to Mac</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF

echo "==> 3. Building 'Switch Mouse Menu Bar.app'..."
MENUBAR_APP="$DIR/Switch Mouse Menu Bar.app"
rm -rf "$MENUBAR_APP"
mkdir -p "$MENUBAR_APP/Contents/MacOS"
mkdir -p "$MENUBAR_APP/Contents/Resources"

cp "$ICNS_FILE" "$MENUBAR_APP/Contents/Resources/AppIcon.icns"
cp "$DIR/switch_mouse.py" "$MENUBAR_APP/Contents/Resources/switch_mouse.py"
chmod +x "$MENUBAR_APP/Contents/Resources/switch_mouse.py"

swiftc "$DIR/MenuBarApp.swift" -o "$MENUBAR_APP/Contents/MacOS/MenuBarApp" -framework Cocoa

cat << 'EOF' > "$MENUBAR_APP/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>MenuBarApp</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.btmouseswitcher.menubar</string>
    <key>CFBundleName</key>
    <string>Switch Mouse Menu Bar</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF

# Clean up temp binary if created
rm -f "$DIR/MenuBarApp"
rm -rf "$BUILD_DIR"

echo "==> Done! Successfully created:"
echo "    - $LAUNCHER_APP"
echo "    - $MENUBAR_APP"
