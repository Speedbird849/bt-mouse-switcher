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
        
        # Background rounded rect
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

echo "==> 2. Building 'Switch Mouse to Mac.app'..."
APP_BUNDLE="$DIR/Switch Mouse to Mac.app"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$ICNS_FILE" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

swiftc "$DIR/App.swift" -o "$APP_BUNDLE/Contents/MacOS/SwitchMouseApp" -framework Cocoa -framework IOBluetooth

cat << 'EOF' > "$APP_BUNDLE/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>SwitchMouseApp</string>
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
</dict>
</plist>
EOF

rm -rf "$BUILD_DIR"

echo "==> Done! Successfully created:"
echo "    - $APP_BUNDLE"
