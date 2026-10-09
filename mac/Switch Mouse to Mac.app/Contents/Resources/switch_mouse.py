#!/usr/bin/env python3
"""
Logitech M337 Bluetooth Mouse Quick Switcher for macOS
Automates:
1. Checking if the mouse is already connected.
2. Unpairing any existing stale pairing profile from macOS Bluetooth settings.
3. Discovering the mouse in pairing mode.
4. Pairing with the mouse.
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

DEFAULT_DEVICE_NAME_PATTERNS = ["Logitech M337", "M337", "Bluetooth Mouse M337"]
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

def is_matching_device(device, target_address=None, target_names=None):
    """Check if device matches target MAC address or name."""
    if not isinstance(device, dict):
        return False
    dev_addr = device.get("address", "").strip().lower()
    dev_name = device.get("name", "").strip().lower()

    if target_address and dev_addr == target_address.strip().lower():
        return True

    if not target_names:
        target_names = DEFAULT_DEVICE_NAME_PATTERNS

    for pattern in target_names:
        if pattern.strip().lower() in dev_name:
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

def unpair_device(address, name="Device"):
    """Unpair device by MAC address."""
    print(f"Unpairing stale {name} ({address})...")
    code, out, err = run_cmd([BLUEUTIL, "--unpair", address])
    # Give macOS Bluetooth daemon a moment to update pairing state
    time.sleep(1.2)
    return code == 0

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
    """Pair with device using blueutil."""
    print(f"Pairing with {address}...")
    # Pipe "yes\n" in case simple pairing confirmation is requested
    code, out, err = run_cmd([BLUEUTIL, "--pair", address], timeout=15, input_data="yes\n")
    time.sleep(0.8)
    return code == 0

def connect_device(address, max_attempts=3):
    """Connect to paired device with retries."""
    print(f"Connecting to {address}...")
    for attempt in range(1, max_attempts + 1):
        run_cmd([BLUEUTIL, "--connect", address], timeout=10)
        time.sleep(1.0)
        code, out, _ = run_cmd([BLUEUTIL, "--is-connected", address])
        if out == "1":
            return True
        print(f"Connection attempt {attempt} not ready yet, retrying...")
        time.sleep(0.5)
    return False

def switch_mouse(target_mac=None, target_names=None, timeout=DEFAULT_TIMEOUT_SEC, silent=False):
    """Main workflow to switch mouse to Mac."""
    if not BLUEUTIL:
        msg = "blueutil not found! Please install it with: brew install blueutil"
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
        name = existing_match.get("name", "Logitech M337")
        if existing_match.get("connected") is True:
            # Check actual live connection
            _, is_conn, _ = run_cmd([BLUEUTIL, "--is-connected", addr])
            if is_conn == "1":
                print(f"{name} ({addr}) is already connected and active.")
                if not silent:
                    notify("Logitech M337", "Mouse is already connected and active!", sound="Glass")
                return 0

        # It is in paired list, but not connected (or link key is obsolete from Windows)
        print(f"Found existing pairing for {name} ({addr}). Removing stale profile...")
        unpair_device(addr, name=name)

    # 2. Prompt user and search for mouse in discovery / pairing mode
    print(f"Searching for mouse (timeout: {timeout}s)...")
    if not silent:
        notify("Switching Mouse to Mac", "Searching for Logitech M337...\nPress pairing button on mouse!", sound="Ping")

    start_time = time.time()
    discovered_target = None
    scan_chunk = 3

    while (time.time() - start_time) < timeout:
        devices = inquiry_scan(duration=scan_chunk)
        for dev in devices:
            if is_matching_device(dev, target_address=known_address, target_names=target_names):
                discovered_target = dev
                break
        if discovered_target:
            break
        print(f"Still searching... (elapsed: {int(time.time() - start_time)}s)")

    if not discovered_target:
        msg = f"Could not find Logitech M337 within {timeout}s. Press the button on the bottom of the mouse and try again!"
        print(msg, file=sys.stderr)
        if not silent:
            notify("Mouse Switch Failed", "Logitech M337 not found.\nPress pairing button underneath mouse and retry.", sound="Basso")
        return 1

    target_addr = discovered_target.get("address")
    target_name = discovered_target.get("name", "Logitech M337")
    print(f"Found {target_name} at {target_addr}!")

    # Update config with discovered address
    config["last_address"] = target_addr
    save_config(config)

    # 3. Pair
    pair_success = pair_device(target_addr)
    if not pair_success:
        print(f"Warning: Pair command returned non-zero, attempting connection anyway...")

    # 4. Connect
    connected = connect_device(target_addr, max_attempts=3)
    if connected:
        success_msg = f"{target_name} connected successfully!"
        print(success_msg)
        if not silent:
            notify("Logitech M337 Connected", "Mouse is now connected and ready to use!", sound="Glass")
        return 0
    else:
        err_msg = f"Paired with {target_name}, but connection timed out. Click mouse buttons to wake it up."
        print(err_msg, file=sys.stderr)
        if not silent:
            notify("Connection Pending", "Paired successfully! Click a mouse button to finish connecting.", sound="Ping")
        return 0

def main():
    parser = argparse.ArgumentParser(description="Logitech M337 Bluetooth Mouse Quick Switcher for macOS")
    parser.add_argument("--name", nargs="*", default=None, help="Device name pattern(s) to match (default: Logitech M337, M337)")
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
