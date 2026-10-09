<#
.SYNOPSIS
    Bluetooth Mouse M336/M337/M535 Quick Switcher for Windows (PowerShell)
.DESCRIPTION
    Automates:
    1. Checking if the Bluetooth Mouse M336/M337/M535 is already connected on Windows.
    2. Unpairing any stale pairing profile.
    3. Scanning for the mouse in pairing mode.
    4. Automatically pairing (handling PIN 0000 and Just Works) and establishing connection.
#>

[CmdletBinding()]
param (
    [string]$DeviceName = "Bluetooth Mouse M336/M337/M535",
    [int]$TimeoutSeconds = 15
)

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host " Bluetooth Mouse M336/M337/M535 Switcher (Windows)" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

# Check if Bluetooth Command Line Tools (btpair) is available as an option
$btpair = Get-Command "btpair.exe" -ErrorAction SilentlyContinue

function Show-Notification {
    param([string]$Title, [string]$Message)
    try {
        [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
        [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null

        $template = @"
<toast>
    <visual>
        <binding template="ToastGeneric">
            <text>$Title</text>
            <text>$Message</text>
        </binding>
    </visual>
</toast>
"@
        $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
        $xml.LoadXml($template)
        $toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
        $notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("Bluetooth Mouse Switcher")
        $notifier.Show($toast)
    } catch {
        Write-Host "[$Title] $Message" -ForegroundColor Yellow
    }
}

# WinRT Bluetooth implementation using embedded C#
$csharpSource = @"
using System;
using System.Threading;
using System.Threading.Tasks;
using Windows.Devices.Enumeration;
using Windows.Devices.Bluetooth;

public class BtSwitcher {
    private const string ExactTarget = "Bluetooth Mouse M336/M337/M535";

    private static bool IsTargetDevice(string name) {
        if (string.IsNullOrWhiteSpace(name)) return false;
        if (name.Equals(ExactTarget, StringComparison.OrdinalIgnoreCase)) return true;
        string n = name.ToLowerInvariant();
        return n.Contains("m336/m337/m535")
            || n.Contains("m337")
            || n.Contains("m336")
            || n.Contains("m535")
            || n.Contains("bluetooth mouse");
    }

    public static async Task<bool> UnpairAsync(string targetName) {
        try {
            string selector = BluetoothDevice.GetDeviceSelectorFromPairingState(true);
            var devices = await DeviceInformation.FindAllAsync(selector);
            foreach (var dev in devices) {
                if (IsTargetDevice(dev.Name) || (!string.IsNullOrEmpty(targetName) && dev.Name.IndexOf(targetName, StringComparison.OrdinalIgnoreCase) >= 0)) {
                    Console.WriteLine("Unpairing stale device: " + dev.Name + " (" + dev.Id + ")");
                    var result = await dev.Pairing.UnpairAsync();
                    Console.WriteLine("Unpair status: " + result.Status);
                    return result.Status == DeviceUnpairingResultStatus.Unpaired || result.Status == DeviceUnpairingResultStatus.AlreadyUnpaired;
                }
            }
        } catch (Exception ex) {
            Console.WriteLine("Error during unpair: " + ex.Message);
        }
        return false;
    }

    public static async Task<bool> PairAsync(string targetName, int timeoutSeconds) {
        try {
            Console.WriteLine("Scanning for Bluetooth Mouse M336/M337/M535 in pairing mode...");
            string selector = BluetoothDevice.GetDeviceSelectorFromPairingState(false);
            var watcher = DeviceInformation.CreateWatcher(selector);

            DeviceInformation foundDevice = null;
            var tcs = new TaskCompletionSource<bool>();

            watcher.Added += (sender, dev) => {
                if (IsTargetDevice(dev.Name) || (!string.IsNullOrEmpty(targetName) && dev.Name.IndexOf(targetName, StringComparison.OrdinalIgnoreCase) >= 0)) {
                    foundDevice = dev;
                    tcs.TrySetResult(true);
                }
            };

            watcher.Start();
            var delayTask = Task.Delay(timeoutSeconds * 1000);
            var completed = await Task.WhenAny(tcs.Task, delayTask);
            watcher.Stop();

            if (foundDevice == null) {
                Console.WriteLine("Device not found within timeout.");
                return false;
            }

            Console.WriteLine("Found device: " + foundDevice.Name + ". Pairing...");
            var customPairing = foundDevice.Pairing.Custom;
            customPairing.PairingRequested += (sender, args) => {
                if (args.PairingKind == DevicePairingKinds.ProvidePin) {
                    args.Accept("0000");
                } else {
                    args.Accept();
                }
            };

            var pairResult = await customPairing.PairAsync(DevicePairingKinds.ConfirmOnly | DevicePairingKinds.ProvidePin);
            Console.WriteLine("Pairing result: " + pairResult.Status);
            return pairResult.Status == DevicePairingResultStatus.Paired || pairResult.Status == DevicePairingResultStatus.AlreadyPaired;
        } catch (Exception ex) {
            Console.WriteLine("Error during pairing: " + ex.Message);
            return false;
        }
    }
}
"@

function Invoke-WinRTSwitch {
    Show-Notification "Switching Mouse to Windows" "Searching for Bluetooth Mouse M336/M337/M535... Press pairing button on mouse."
    
    # Unpair
    [BtSwitcher]::UnpairAsync($DeviceName).GetAwaiter().GetResult() | Out-Null
    Start-Sleep -Milliseconds 800

    # Pair
    $success = [BtSwitcher]::PairAsync($DeviceName, $TimeoutSeconds).GetAwaiter().GetResult()
    if ($success) {
        Write-Host "Bluetooth Mouse M336/M337/M535 paired and connected successfully." -ForegroundColor Green
        Show-Notification "Bluetooth Mouse Connected" "Mouse is connected and ready to use on Windows."
    } else {
        Write-Host "Failed to find or pair Bluetooth Mouse M336/M337/M535." -ForegroundColor Red
        Show-Notification "Mouse Switch Failed" "Bluetooth Mouse M336/M337/M535 not found. Make sure the pairing button was pressed."
    }
}

# If btpair CLI tool is available, use it; otherwise use WinRT
if ($btpair) {
    Write-Host "Using btpair CLI..." -ForegroundColor Gray
    Show-Notification "Switching Mouse to Windows" "Searching for Bluetooth Mouse M336/M337/M535... Press pairing button on mouse."
    
    # 1. Unpair
    & btpair -u -n "Bluetooth Mouse M336/M337/M535" 2>$null | Out-Null
    & btpair -u -n $DeviceName 2>$null | Out-Null
    Start-Sleep -Milliseconds 800

    # 2. Pair with PIN 0000 or default
    $result = & btpair -p -n "Bluetooth Mouse M336/M337/M535" -b "0000"
    if ($LASTEXITCODE -ne 0) {
        $result = & btpair -p -n "Bluetooth Mouse M336/M337/M535"
    }

    if ($LASTEXITCODE -eq 0) {
        Write-Host "Connected successfully via btpair." -ForegroundColor Green
        Show-Notification "Bluetooth Mouse Connected" "Mouse is connected and ready to use."
    } else {
        Write-Host "btpair failed, falling back to WinRT..." -ForegroundColor Yellow
        Add-Type -TypeDefinition $csharpSource
        Invoke-WinRTSwitch
    }
} else {
    try {
        Add-Type -TypeDefinition $csharpSource
        Invoke-WinRTSwitch
    } catch {
        Write-Error "Failed to initialize WinRT Bluetooth: $_"
        Write-Host "Tip: You can also install Bluetooth Command Line Tools (btpair) from https://bluetoothinstaller.com" -ForegroundColor Yellow
    }
}
