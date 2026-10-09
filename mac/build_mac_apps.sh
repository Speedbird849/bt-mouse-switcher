#!/bin/bash
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$DIR/build"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> 1. Generating App Icon..."
rm -f /tmp/BTMouseIcon.icns
python3 - << 'EOF'
import Cocoa, os, subprocess

iconset_dir = '/tmp/BTMouseIcon.iconset'
os.makedirs(iconset_dir, exist_ok=True)

sizes = [16, 32, 64, 128, 256, 512]
for s in sizes:
    for scale in [1, 2]:
        px = s * scale
        name = f"icon_{s}x{s}.png" if scale == 1 else f"icon_{s}x{s}@2x.png"
        img = Cocoa.NSImage.alloc().initWithSize_((float(px), float(px)))
        img.lockFocus()
        
        # Background rounded rect (original deep blue background as-is)
        bg = Cocoa.NSColor.colorWithCalibratedRed_green_blue_alpha_(0.12, 0.48, 0.90, 1.0)
        bg.setFill()
        path = Cocoa.NSBezierPath.bezierPathWithRoundedRect_xRadius_yRadius_(
            ((0.0, 0.0), (float(px), float(px))), float(px) * 0.22, float(px) * 0.22
        )
        path.fill()
        
        # SF Symbol computermouse.fill - light blue icon
        sym = Cocoa.NSImage.imageWithSystemSymbolName_accessibilityDescription_('computermouse.fill', None)
        if sym:
            light_blue = Cocoa.NSColor.colorWithCalibratedRed_green_blue_alpha_(0.45, 0.82, 1.0, 1.0)
            sym_config = Cocoa.NSImageSymbolConfiguration.configurationWithPointSize_weight_(float(px) * 0.55, 5)
            color_config = Cocoa.NSImageSymbolConfiguration.configurationWithHierarchicalColor_(light_blue)
            sym = sym.imageWithSymbolConfiguration_(sym_config.configurationByApplyingConfiguration_(color_config))
            
            rect = ((float(px) * 0.225, float(px) * 0.225), (float(px) * 0.55, float(px) * 0.55))
            zero = ((0.0, 0.0), (0.0, 0.0))
            sym.drawInRect_fromRect_operation_fraction_(
                rect, zero, Cocoa.NSCompositingOperationSourceOver, 1.0
            )
            
        img.unlockFocus()
        
        tiff = img.TIFFRepresentation()
        bitmap = Cocoa.NSBitmapImageRep.imageRepWithData_(tiff)
        png = bitmap.representationUsingType_properties_(Cocoa.NSPNGFileType, {})
        png.writeToFile_atomically_(os.path.join(iconset_dir, name), True)

subprocess.run(['iconutil', '-c', 'icns', iconset_dir, '-o', '/tmp/BTMouseIcon.icns'], check=True)
EOF

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
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>Bluetooth Mouse Switcher needs Bluetooth access to discover, unpair, and connect your Bluetooth mouse.</string>
    <key>NSBluetoothPeripheralUsageDescription</key>
    <string>Bluetooth Mouse Switcher needs Bluetooth access to discover, unpair, and connect your Bluetooth mouse.</string>
</dict>
</plist>
EOF

rm -rf "$BUILD_DIR"

echo "==> Done! Successfully created:"
echo "    - $APP_BUNDLE"
