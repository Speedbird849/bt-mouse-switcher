# Logitech M336/M337/M535 Quick Switcher

A 1-click solution to seamlessly switch a single-host Bluetooth mouse, between macOS and Windows without ever manually digging into Bluetooth Settings.

---

## The Problem
The M336/M337/M535 mouse is a single-host Bluetooth device (it does not have multi-device host switching buttons like the MX Master). When paired to Computer B, its internal Link Key is overwritten. When switching back to Computer A, the host's existing pairing key is rejected by the mouse, requiring the user to manually:
1. Open Bluetooth Settings.
2. Find the mouse and click "Forget Device / Unpair".
3. Put the mouse into pairing mode.
4. Scan and re-pair.

## The Solution
This tool automates the entire cycle into a single click:
1. Checks if the mouse is already active.
2. Automatically forgets / unpairs the stale device profile and link keys.
3. Discovers the mouse in pairing mode (matching the exact name "Bluetooth Mouse M336/M337/M535").
4. Pairs and connects to it automatically (handling PIN 0000 and Simple Pairing).
5. Displays native system notifications and audio feedback.

---

## macOS Setup

The applications are located in your `/Applications` folder:
- `/Applications/Switch Mouse to Mac.app`
- `/Applications/Switch Mouse Menu Bar.app`

### 4 Ways to Trigger in a Single Click:

1. **Spotlight / Raycast / Alfred:**
   - Press <kbd>Cmd</kbd> + <kbd>Space</kbd> and type `Switch Mouse to Mac`. Hit <kbd>Enter</kbd>.
2. **macOS Dock:**
   - Drag `/Applications/Switch Mouse to Mac.app` into your Dock for a permanent 1-click icon.
3. **Menu Bar App:**
   - Launch `/Applications/Switch Mouse Menu Bar.app`.
   - A `Mouse` icon will sit in your macOS menu bar with live connection status (`[ON]` / `[OFF]`) and a 1-click `Switch to Mac (Pair & Connect)` button.
   - (To keep it running at startup: add it to *System Settings > General > Login Items*).
4. **Terminal / Shell:**
   - Run `bt-mouse-switch` from any terminal window.

### Switching Routine on Mac
1. Press the Bluetooth button on the bottom of the mouse (blue LED blinks fast).
2. Click **Switch Mouse to Mac** (or click it in the Menu Bar / Spotlight / Dock).
3. The mouse will unpair the old profile, discover the mouse, pair, and connect.

---

## Windows Setup

The Windows solution is ready in the [`windows/`](windows) directory:

1. Copy the [`windows`](windows) folder to your Windows laptop.
2. Right-click [`Switch-Mouse.bat`](windows/Switch-Mouse.bat) -> **Send to -> Desktop (create shortcut)**.
3. Rename the desktop shortcut to **"Switch Mouse to Windows"**.

### Switching Routine on Windows
1. Press the Bluetooth button underneath the mouse (blue LED blinks fast).
2. Double-click **"Switch Mouse to Windows"** on your desktop.
3. The script automatically removes the old profile, pairs with the mouse, and shows a Windows notification when connected.

---

## Directory Structure
```
bt-mouse-switcher/
├── mac/
│   ├── switch_mouse.py             # Core switching engine (Python 3 + blueutil)
│   ├── MenuBarApp.swift            # Native macOS menu bar status item (Swift)
│   ├── build_mac_apps.sh           # App packager and icon generator
│   ├── install_mac.sh              # One-step installer
│   ├── Switch Mouse to Mac.app     # One-click desktop/dock app
│   └── Switch Mouse Menu Bar.app   # Menu bar status item app
├── windows/
│   ├── Switch-Mouse.ps1            # Windows Bluetooth WinRT / btpair switcher
│   ├── Switch-Mouse.bat            # Windows batch shortcut launcher
│   └── README-Windows.md           # Windows setup guide
└── README.md
```
