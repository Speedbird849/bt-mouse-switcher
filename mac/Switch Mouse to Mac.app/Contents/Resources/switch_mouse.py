#!/usr/bin/env python3
"""
Bluetooth Mouse M336/M337/M535 Quick Switcher for macOS
Automates:
1. Checking if the mouse is already connected.
2. Unpairing any stale pairing profile from macOS Bluetooth settings.
3. Discovering the mouse in pairing mode.
4. Pairing with the mouse (handles PIN 0000 and simple pairing).
5. Connecting to the mouse and confirming active connection.
"""

import os
import sys
import time
import json
import shutil
import argparse
import subprocess
from pathlib import Path

CONFIG_DIR = Path.home() / ".config" / "bt-mouse-switcher"
CONFIG_FILE = CONFIG_DIR / "config.json"

EXACT_DEVICE_NAME = "Bluetooth Mouse M336/M337/M535"

DEFAULT_DEVICE_NAME_PATTERNS = [
    EXACT_DEVICE_NAME,
    "M336/M337/M535",
    "M337",
    "M336",
    "M535",
    "Bluetooth Mouse",
]
DEFAULT_TIMEOUT_SEC = 15

def get_blueutil_path():
    """Find blueutil executable."""
    locations = [
        shutil.which("blueutil"),
        "/opt/homebrew/bin/blueutil",
        "/usr/local/bin/blueutil",
    ]
    for loc in locations:
        if loc and os.path.isfile(loc) and os.access(loc, os.X_OK):
            return loc
    return None

BLUEUTIL = get_blueutil_path()

def notify(title, message, sound=None):
    """Display native macOS notification and optionally play sound."""
    escaped_title = title.replace('"', '\\"')
    escaped_message = message.replace('"', '\\"')
    script = f'display notification "{escaped_message}" with title "{escaped_title}"'
    subprocess.run(["osascript", "-e", script], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if sound:
        sound_path = f"/System/Library/Sounds/{sound}.aiff"
        if os.path.exists(sound_path):
            subprocess.Popen(["afplay", sound_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

def load_config():
    """Load cached device configuration."""
    if CONFIG_FILE.exists():
        try:
            with open(CONFIG_FILE, "r") as f:
                return json.load(f)
        except Exception:
            pass
    return {"last_address": None, "target_names": DEFAULT_DEVICE_NAME_PATTERNS}

def save_config(config):
    """Save cached device configuration."""
    try:
        CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        with open(CONFIG_FILE, "w") as f:
            json.dump(config, f, indent=2)
    except Exception as e:
        print(f"Warning: Failed to save config: {e}", file=sys.stderr)

def run_cmd(args, timeout=10, input_data=None):
    """Run a CLI command and return stdout string."""
    try:
        res = subprocess.run(
            args,
            input=input_data,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout
        )
        return res.returncode, res.stdout.strip(), res.stderr.strip()
    except subprocess.TimeoutExpired:
        return -1, "", "Timeout expired"
    except Exception as e:
        return -1, "", str(e)

def get_iobluetooth_device(address):
    """Get IOBluetoothDevice instance if PyObjC is available."""
    try:
        import objc
        from Foundation import NSBundle
        bundle = NSBundle.bundleWithPath_("/System/Library/Frameworks/IOBluetooth.framework")
        if bundle:
            bundle.load()
            IOBluetoothDevice = objc.lookUpClass("IOBluetoothDevice")
            if IOBluetoothDevice:
                return IOBluetoothDevice.deviceWithAddressString_(address)
    except Exception:
        pass
    return None

def resolve_device_name(address):
    """Attempt to resolve device name if missing from scan."""
    dev = get_iobluetooth_device(address)
    if dev:
        try:
            name = dev.name() or dev.nameOrAddress()
            if name and name.lower() != address.lower().replace("-", ":"):
                return name
        except Exception:
            pass
    code, out, _ = run_cmd([BLUEUTIL, "--info", address, "--format", "json"], timeout=4)
    if code == 0 and out:
        try:
            info = json.loads(out)
            return info.get("name")
        except Exception:
            pass
    return None

def is_mouse_device(address):
    """Check if device class indicates a mouse / pointing device peripheral."""
    dev = get_iobluetooth_device(address)
    if dev:
        try:
            major = getattr(dev, "deviceClassMajor", lambda: 0)()
            minor = getattr(dev, "deviceClassMinor", lambda: 0)()
            # Major 5 = Peripheral, Minor 2 = Pointing device / mouse
            if major == 5 and minor == 2:
                return True
        except Exception:
            pass
    return False

def is_matching_device(device, target_address=None, target_names=None, check_peripheral_type=False):
    """Check if device matches target MAC address, exact name, or patterns."""
    if not isinstance(device, dict):
        return False
    dev_addr = (device.get("address") or "").strip().lower()
    dev_name = (device.get("name") or "").strip()

    if target_address and dev_addr == target_address.strip().lower():
        return True

    # 1. Exact match check (case-insensitive)
    if dev_name.lower() == EXACT_DEVICE_NAME.lower():
        return True

    # 2. Pattern check
    if not target_names:
        target_names = DEFAULT_DEVICE_NAME_PATTERNS

    dev_name_lower = dev_name.lower()
    for pattern in target_names:
        p = pattern.strip().lower()
        if p and p in dev_name_lower:
            return True

    # 3. If name is not yet resolved, query the device directly
    if not dev_name or dev_name.lower() == dev_addr.replace("-", ":"):
        resolved = resolve_device_name(dev_addr)
        if resolved:
            resolved_lower = resolved.strip().lower()
            if resolved_lower == EXACT_DEVICE_NAME.lower():
                return True
            for pattern in target_names:
                p = pattern.strip().lower()
                if p and p in resolved_lower:
                    return True

    # 4. If enabled, check if device class is a mouse
    if check_peripheral_type and is_mouse_device(dev_addr):
        return True

    return False

def check_bluetooth_power():
    """Ensure macOS Bluetooth is powered on."""
    code, stdout, _ = run_cmd([BLUEUTIL, "-p"])
    if stdout == "0":
        print("Bluetooth is currently OFF. Turning it ON...")
        run_cmd([BLUEUTIL, "-p", "1"])
        time.sleep(1.0)

def get_paired_devices():
    """List paired Bluetooth devices."""
    code, stdout, _ = run_cmd([BLUEUTIL, "--paired", "--format", "json"])
    if code == 0 and stdout:
        try:
            return json.loads(stdout)
        except json.JSONDecodeError:
            pass
    return []

def unpair_device(address, name=EXACT_DEVICE_NAME):
    """Unpair device and remove link keys from macOS Bluetooth."""
    print(f"Unpairing stale {name} ({address})...")
    # Method 1: PyObjC direct IOBluetooth removal
    dev = get_iobluetooth_device(address)
    if dev:
        try:
            if hasattr(dev, "removeLinkKey"):
                dev.removeLinkKey()
            if hasattr(dev, "forceRemove"):
                dev.forceRemove()
            elif hasattr(dev, "remove"):
                dev.remove()
        except Exception as e:
            print(f"IOBluetooth unpair note: {e}", file=sys.stderr)

    # Method 2: blueutil unpair
    run_cmd([BLUEUTIL, "--unpair", address], timeout=5)

    # Allow macOS Bluetooth daemon to clear pairing database
    time.sleep(1.0)
    return True

def inquiry_scan(duration=4):
    """Perform a short Bluetooth inquiry scan."""
    code, stdout, _ = run_cmd([BLUEUTIL, "--inquiry", str(duration), "--format", "json"], timeout=duration + 5)
    if code == 0 and stdout:
        try:
            return json.loads(stdout)
        except json.JSONDecodeError:
            pass
    return []

def pair_device(address):
    """Pair with device using blueutil (handles PIN 0000 and SSP user confirmation)."""
    print(f"Pairing with {address}...")

    # 1. Try pairing with PIN '0000' (standard for Bluetooth Mouse M336/M337/M535)
    code, out, err = run_cmd([BLUEUTIL, "--pair", address, "0000"], timeout=15, input_data="yes\n")
    if code == 0:
        print("Pairing successful.")
        time.sleep(1.0)
        return True

    # 2. Try pairing without explicit PIN (SSP Just Works)
    print("Retrying pairing without explicit PIN...")
    code, out, err = run_cmd([BLUEUTIL, "--pair", address], timeout=15, input_data="yes\n")
    if code == 0:
        print("Pairing successful.")
        time.sleep(1.0)
        return True

    # 3. Check if device is paired anyway
    code, out, _ = run_cmd([BLUEUTIL, "--info", address, "--format", "json"], timeout=5)
    if code == 0 and out:
        try:
            info = json.loads(out)
            if info.get("paired") is True:
                print("Device confirmed paired.")
                return True
        except Exception:
            pass

    return False

def connect_device(address, max_attempts=4):
    """Connect to paired device with retries."""
    print(f"Connecting to {address}...")
    for attempt in range(1, max_attempts + 1):
        run_cmd([BLUEUTIL, "--connect", address], timeout=8)
        time.sleep(1.2)
        code, out, _ = run_cmd([BLUEUTIL, "--is-connected", address], timeout=4)
        if out == "1":
            return True

        # Fallback: attempt direct openConnection via IOBluetooth
        dev = get_iobluetooth_device(address)
        if dev and hasattr(dev, "openConnection"):
            try:
                dev.openConnection()
            except Exception:
                pass

        time.sleep(1.0)
        code, out, _ = run_cmd([BLUEUTIL, "--is-connected", address], timeout=4)
        if out == "1":
            return True

        print(f"Connection attempt {attempt}/{max_attempts} pending, retrying...")

    return False

def switch_mouse(target_mac=None, target_names=None, timeout=DEFAULT_TIMEOUT_SEC, silent=False):
    """Main workflow to switch mouse to Mac."""
    if not BLUEUTIL:
        msg = "blueutil not found. Please install it with: brew install blueutil"
        print(msg, file=sys.stderr)
        if not silent:
            notify("Bluetooth Mouse Switcher Error", msg, sound="Basso")
        return 1

    check_bluetooth_power()

    config = load_config()
    if target_mac:
        known_address = target_mac
    else:
        known_address = config.get("last_address")

    if not target_names:
        target_names = config.get("target_names", DEFAULT_DEVICE_NAME_PATTERNS)

    # 1. Check if device is already paired
    paired = get_paired_devices()
    existing_match = None
    for dev in paired:
        if is_matching_device(dev, target_address=known_address, target_names=target_names):
            existing_match = dev
            break

    if existing_match:
        addr = existing_match.get("address")
        name = existing_match.get("name") or EXACT_DEVICE_NAME
        if existing_match.get("connected") is True:
            _, is_conn, _ = run_cmd([BLUEUTIL, "--is-connected", addr])
            if is_conn == "1":
                print(f"{name} ({addr}) is already connected and active.")
                if not silent:
                    notify(EXACT_DEVICE_NAME, "Mouse is already connected and active.", sound="Glass")
                return 0

        # Found stale pairing profile, unpair it
        print(f"Found existing pairing for {name} ({addr}). Removing stale profile...")
        unpair_device(addr, name=name)

    # 2. Search for mouse in pairing mode
    print(f"Searching for mouse (timeout: {timeout}s)...")
    if not silent:
        notify("Switching Mouse to Mac", f"Searching for {EXACT_DEVICE_NAME}...\nPress pairing button on mouse.", sound="Ping")

    start_time = time.time()
    discovered_target = None
    scan_chunk = 3

    while (time.time() - start_time) < timeout:
        devices = inquiry_scan(duration=scan_chunk)
        for dev in devices:
            if is_matching_device(dev, target_address=known_address, target_names=target_names, check_peripheral_type=True):
                discovered_target = dev
                break
        if discovered_target:
            break
        print(f"Still searching... (elapsed: {int(time.time() - start_time)}s)")

    if not discovered_target:
        msg = f"Could not find {EXACT_DEVICE_NAME} within {timeout}s. Press the button underneath the mouse and try again."
        print(msg, file=sys.stderr)
        if not silent:
            notify("Mouse Switch Failed", f"{EXACT_DEVICE_NAME} not found.\nPress pairing button underneath mouse and retry.", sound="Basso")
        return 1

    target_addr = discovered_target.get("address")
    target_name = discovered_target.get("name") or resolve_device_name(target_addr) or EXACT_DEVICE_NAME
    print(f"Found {target_name} at {target_addr}!")

    # Update config with discovered address
    config["last_address"] = target_addr
    save_config(config)

    # 3. Pair
    pair_success = pair_device(target_addr)
    if not pair_success:
        print("Warning: Pair command returned non-zero, attempting connection anyway...")

    # 4. Connect
    connected = connect_device(target_addr, max_attempts=4)
    if connected:
        success_msg = f"{target_name} connected successfully!"
        print(success_msg)
        if not silent:
            notify(f"{EXACT_DEVICE_NAME} Connected", "Mouse is now connected and ready to use.", sound="Glass")
        return 0
    else:
        err_msg = f"Paired with {target_name}, but connection timed out. Click mouse buttons to wake it up."
        print(err_msg, file=sys.stderr)
        if not silent:
            notify("Connection Pending", "Paired successfully. Click a mouse button to finish connecting.", sound="Ping")
        return 0

def main():
    parser = argparse.ArgumentParser(description="Bluetooth Mouse M336/M337/M535 Quick Switcher for macOS")
    parser.add_argument("--name", nargs="*", default=None, help="Device name pattern(s) to match")
    parser.add_argument("--mac", default=None, help="Explicit Bluetooth MAC address (e.g. xx-xx-xx-xx-xx-xx)")
    parser.add_argument("--timeout", type=int, default=DEFAULT_TIMEOUT_SEC, help="Search timeout in seconds (default: 15)")
    parser.add_argument("--silent", action="store_true", help="Suppress notifications and audio chimes")
    args = parser.parse_args()

    return switch_mouse(
        target_mac=args.mac,
        target_names=args.name,
        timeout=args.timeout,
        silent=args.silent
    )

if __name__ == "__main__":
    sys.exit(main())
