# Logitech M336/M337/M535 Quick Switcher

A one-click solution to seamlessly switch a single-host Bluetooth mouse between macOS and Windows without ever manually digging into Bluetooth Settings.

---

## The Problem
The M336/M337/M535 mouse is a single-host Bluetooth device (it does not have multi-device host switching buttons like the MX Master). When paired to Computer B, its internal Link Key is overwritten. When switching back to Computer A, the host's existing pairing key is rejected by the mouse, requiring the user to manually:
1. Open Bluetooth Settings.
2. Find the mouse and click "Forget Device / Unpair".
3. Put the mouse into pairing mode.
4. Scan and re-pair.

## The Solution
This tool automates the entire cycle into a single click:
1. Disconnects and completely forgets `Bluetooth Mouse M336/M337/M535` from macOS Bluetooth settings (clearing link keys).
2. Waits a second for the Bluetooth subsystem to reset.
3. Searches for the device again in pairing mode.
4. Pairs and connects to it automatically.

---

## macOS Setup

The application is installed in `/Applications`:
- `/Applications/Switch Mouse to Mac.app`

### Using the App:
1. **Launch the App:** Open `/Applications/Switch Mouse to Mac.app` (or launch via Spotlight: <kbd>Cmd</kbd> + <kbd>Space</kbd> -> `Switch Mouse to Mac`).
2. **Put the mouse into pairing mode:** Press the Bluetooth button on the bottom of the mouse (blue LED blinks rapidly).
3. **Click the Button:** Click **"Disconnect, Forget & Reconnect"** in the app window.
4. The app handles disconnecting, forgetting, searching, pairing, and reconnecting automatically with live progress.

You can also drag `/Applications/Switch Mouse to Mac.app` to your macOS Dock for fast 1-click access anytime.

### Command Line
Run `bt-mouse-switch` from any terminal window (or `python3 mac/switch_mouse.py`).

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
│   ├── App.swift                   # Native macOS UI App (Swift)
│   ├── switch_mouse.py             # CLI switching script (Python 3 + blueutil)
│   ├── build_mac_apps.sh           # App packager and icon generator
│   ├── install_mac.sh              # One-step installer
│   └── Switch Mouse to Mac.app     # Window application bundle
├── windows/
│   ├── Switch-Mouse.ps1            # Windows Bluetooth WinRT / btpair switcher
│   ├── Switch-Mouse.bat            # Windows batch shortcut launcher
│   └── README-Windows.md           # Windows setup guide
└── README.md
```
