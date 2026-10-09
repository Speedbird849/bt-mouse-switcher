<#
.SYNOPSIS
    Logitech M337 Quick Switcher for Windows (PowerShell)
.DESCRIPTION
    Automates:
    1. Checking if the Logitech M337 is already connected on Windows.
    2. Unpairing any stale Logitech M337 pairing profile.
    3. Scanning for the mouse in pairing mode.
    4. Automatically pairing and establishing connection.
#>

[CmdletBinding()]
param (
    [string]$DeviceName = "Logitech M337",
    [int]$TimeoutSeconds = 15
)

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host " Logitech M337 Mouse Switcher for Windows" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

# 1. Check if Bluetooth Command Line Tools (btpair) is available as an option
$btpair = Get-Command "btpair.exe" -ErrorAction SilentlyContinue

function Show-Notification {
    param([string]$Title, [string]$Message)
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
    try {
        $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
        $xml.LoadXml($template)
        $toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
        $notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("Logitech M337 Switcher")
        $notifier.Show($toast)
    } catch {
        # Fallback to console
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
    public static async Task<bool> UnpairAsync(string targetName) {
        try {
            string selector = BluetoothDevice.GetDeviceSelectorFromPairingState(true);
            var devices = await DeviceInformation.FindAllAsync(selector);
            foreach (var dev in devices) {
                if (dev.Name.IndexOf(targetName, StringComparison.OrdinalIgnoreCase) >= 0 ||
                    dev.Name.IndexOf("M337", StringComparison.OrdinalIgnoreCase) >= 0) {
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
            Console.WriteLine("Scanning for " + targetName + " in pairing mode...");
            string selector = BluetoothDevice.GetDeviceSelectorFromPairingState(false);
            var watcher = DeviceInformation.CreateWatcher(selector);

            DeviceInformation foundDevice = null;
            var tcs = new TaskCompletionSource<bool>();

            watcher.Added += (sender, dev) => {
                if (dev.Name.IndexOf(targetName, StringComparison.OrdinalIgnoreCase) >= 0 ||
                    dev.Name.IndexOf("M337", StringComparison.OrdinalIgnoreCase) >= 0) {
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
                args.Accept();
            };

            var pairResult = await customPairing.PairAsync(DevicePairingKinds.ConfirmOnly);
            Console.WriteLine("Pairing result: " + pairResult.Status);
            return pairResult.Status == DevicePairingResultStatus.Paired || pairResult.Status == DevicePairingResultStatus.AlreadyPaired;
        } catch (Exception ex) {
            Console.WriteLine("Error during pairing: " + ex.Message);
            return false;
        }
    }
}
"@

# Helper function to run C# Bluetooth switcher
function Invoke-WinRTSwitch {
    Show-Notification "Switching Mouse to Windows" "Searching for Logitech M337... Press pairing button on mouse!"
    
    # Unpair
    [BtSwitcher]::UnpairAsync($DeviceName).GetAwaiter().GetResult() | Out-Null
    Start-Sleep -Milliseconds 800

    # Pair
    $success = [BtSwitcher]::PairAsync($DeviceName, $TimeoutSeconds).GetAwaiter().GetResult()
    if ($success) {
        Write-Host "Logitech M337 paired and connected successfully!" -ForegroundColor Green
        Show-Notification "Logitech M337 Connected" "Mouse is connected and ready to use on Windows!"
    } else {
        Write-Host "Failed to find or pair Logitech M337." -ForegroundColor Red
        Show-Notification "Mouse Switch Failed" "Logitech M337 not found. Make sure the pairing button was pressed."
    }
}

# If btpair CLI tool is available, use it for quick switching; otherwise use WinRT
if ($btpair) {
    Write-Host "Using btpair CLI..." -ForegroundColor Gray
    Show-Notification "Switching Mouse to Windows" "Searching for Logitech M337... Press pairing button on mouse!"
    
    # 1. Unpair
    & btpair -u -n $DeviceName 2>$null | Out-Null
    Start-Sleep -Milliseconds 800

    # 2. Pair
    $result = & btpair -p -n $DeviceName
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Connected successfully via btpair!" -ForegroundColor Green
        Show-Notification "Logitech M337 Connected" "Mouse is connected and ready to use!"
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
