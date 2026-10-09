# Bluetooth Mouse M336/M337/M535 Quick Switcher for Windows

This script automates unpairing the old profile and pairing/connecting to the mouse when switching back to your Windows laptop.

The mouse appears in your Bluetooth device list as **Bluetooth Mouse M336/M337/M535**.

## How to Use (One-Click)

1. Put the `windows` folder onto your Windows PC (e.g. in `C:\Tools\bt-mouse-switcher` or Documents).
2. Right-click `Switch-Mouse.bat` -> Send to -> Desktop (create shortcut).
3. Rename the shortcut to "Switch Mouse to Windows".

### Switching Workflow
1. Press the Bluetooth button on the bottom of your mouse (the blue LED starts blinking rapidly).
2. Double-click "Switch Mouse to Windows" on your Desktop.
3. The script will:
   - Unpair any existing stale mouse connection.
   - Scan for the mouse in pairing mode.
   - Pair and connect automatically (handling PIN 0000 and simple pairing).
   - Show a Windows toast notification when done.

## Requirements
- Windows 10 or Windows 11.
- Bluetooth enabled.
- (Optional but recommended): Bluetooth Command Line Tools (btpair) from https://bluetoothinstaller.com/bluetooth-command-line-tools. If installed, the script uses btpair for ultra-fast switching. If not installed, the script uses Windows built-in WinRT Bluetooth APIs.
