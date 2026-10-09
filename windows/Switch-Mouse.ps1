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

function Initialize-WinRT {
    Add-Type -AssemblyName System.Runtime.WindowsRuntime -ErrorAction Stop
    [Windows.Devices.Enumeration.DeviceInformation, Windows.Devices.Enumeration, ContentType = WindowsRuntime] | Out-Null
    [Windows.Devices.Enumeration.DeviceInformationKind, Windows.Devices.Enumeration, ContentType = WindowsRuntime] | Out-Null
    [Windows.Devices.Enumeration.DeviceInformationCollection, Windows.Devices.Enumeration, ContentType = WindowsRuntime] | Out-Null
    [Windows.Devices.Enumeration.DevicePairingResult, Windows.Devices.Enumeration, ContentType = WindowsRuntime] | Out-Null
    [Windows.Devices.Enumeration.DeviceUnpairingResult, Windows.Devices.Enumeration, ContentType = WindowsRuntime] | Out-Null
    [Windows.Devices.Enumeration.DeviceInformationCustomPairing, Windows.Devices.Enumeration, ContentType = WindowsRuntime] | Out-Null
    [Windows.Devices.Enumeration.DevicePairingRequestedEventArgs, Windows.Devices.Enumeration, ContentType = WindowsRuntime] | Out-Null
    [Windows.Devices.Enumeration.DeviceInformationUpdate, Windows.Devices.Enumeration, ContentType = WindowsRuntime] | Out-Null
    [Windows.Devices.Bluetooth.BluetoothDevice, Windows.Devices.Bluetooth, ContentType = WindowsRuntime] | Out-Null

    $script:AsTaskGeneric = [System.WindowsRuntimeSystemExtensions].GetMethods() |
        Where-Object {
            $_.Name -eq 'AsTask' -and $_.IsGenericMethod -and
            $_.GetGenericArguments().Count -eq 1 -and $_.GetParameters().Count -eq 1 -and
            $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
        } |
        Select-Object -First 1

    if (-not ([System.Management.Automation.PSTypeName]'BluetoothSwitcherHelper').Type) {
        $csharp = @"
using System;
using System.Collections.Generic;
using System.Reflection;
using System.Threading;

public class BluetoothSwitcherHelper {
    public static object TargetDevice = null;
    public static string TargetNameFilter = "";
    public static ManualResetEvent DeviceFoundEvent = new ManualResetEvent(false);
    private static readonly Dictionary<string, object> DiscoveredDevices = new Dictionary<string, object>(StringComparer.OrdinalIgnoreCase);

    public static void Reset(string targetFilter) {
        lock (typeof(BluetoothSwitcherHelper)) {
            TargetDevice = null;
            TargetNameFilter = targetFilter ?? "";
            DeviceFoundEvent.Reset();
            DiscoveredDevices.Clear();
        }
    }

    public static bool Matches(string name) {
        if (string.IsNullOrEmpty(name)) return false;
        string lower = name.ToLowerInvariant();
        if (lower.Contains("m336") || lower.Contains("m337") || lower.Contains("m535") || lower.Contains("bluetooth mouse"))
            return true;
        if (!string.IsNullOrEmpty(TargetNameFilter) && lower.Contains(TargetNameFilter.ToLowerInvariant()))
            return true;
        return false;
    }

    public static void OnDeviceAdded(object sender, object device) {
        if (device == null) return;
        try {
            Type t = device.GetType();
            PropertyInfo nameProp = t.GetProperty("Name");
            string name = nameProp != null ? (nameProp.GetValue(device, null) as string) : null;
            PropertyInfo idProp = t.GetProperty("Id");
            string id = idProp != null ? (idProp.GetValue(device, null) as string) : null;

            if (string.IsNullOrEmpty(name)) {
                PropertyInfo propsProp = t.GetProperty("Properties");
                var props = propsProp != null ? (propsProp.GetValue(device, null) as System.Collections.Generic.IReadOnlyDictionary<string, object>) : null;
                if (props != null && props.ContainsKey("System.ItemNameDisplay")) {
                    name = props["System.ItemNameDisplay"] as string;
                }
            }

            lock (typeof(BluetoothSwitcherHelper)) {
                if (id != null) DiscoveredDevices[id] = device;
                if (Matches(name)) {
                    if (TargetDevice == null) {
                        TargetDevice = device;
                        DeviceFoundEvent.Set();
                    }
                }
            }
        } catch {}
    }

    public static void OnDeviceUpdated(object sender, object update) {
        if (update == null) return;
        try {
            Type t = update.GetType();
            PropertyInfo idProp = t.GetProperty("Id");
            string id = idProp != null ? (idProp.GetValue(update, null) as string) : null;
            PropertyInfo propsProp = t.GetProperty("Properties");
            var props = propsProp != null ? (propsProp.GetValue(update, null) as System.Collections.Generic.IReadOnlyDictionary<string, object>) : null;
            if (props != null && props.ContainsKey("System.ItemNameDisplay")) {
                string name = props["System.ItemNameDisplay"] as string;
                if (Matches(name)) {
                    lock (typeof(BluetoothSwitcherHelper)) {
                        if (TargetDevice == null && id != null && DiscoveredDevices.ContainsKey(id)) {
                            TargetDevice = DiscoveredDevices[id];
                            DeviceFoundEvent.Set();
                        }
                    }
                }
            }
        } catch {}
    }

    public static void OnPairingRequested(object sender, object args) {
        if (args == null) return;
        try {
            Type t = args.GetType();
            PropertyInfo kindProp = t.GetProperty("PairingKind");
            object kindVal = kindProp != null ? kindProp.GetValue(args, null) : null;
            if (kindVal != null && kindVal.ToString() == "ProvidePin") {
                MethodInfo acceptMethod = t.GetMethod("Accept", new Type[] { typeof(string) });
                if (acceptMethod != null) acceptMethod.Invoke(args, new object[] { "0000" });
            } else {
                MethodInfo acceptMethod = t.GetMethod("Accept", new Type[0]);
                if (acceptMethod != null) acceptMethod.Invoke(args, null);
            }
        } catch (Exception ex) {
            Console.WriteLine("PairingRequested error: " + ex.Message);
        }
    }
}
"@
        Add-Type -TypeDefinition $csharp -ErrorAction Stop
    }
}

function Await-WinRTOperation {
    param(
        [Parameter(Mandatory)]$Operation,
        [Parameter(Mandatory)][type]$ResultType
    )

    $task = $script:AsTaskGeneric.MakeGenericMethod($ResultType).Invoke($null, @($Operation))
    return $task.GetAwaiter().GetResult()
}

function Test-TargetDevice {
    param([string]$Name, [string]$TargetName)
    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
    return $Name -match "(?i)m336/m337/m535|m337|m336|m535|bluetooth mouse" -or
        (![string]::IsNullOrEmpty($TargetName) -and $Name.IndexOf($TargetName, [StringComparison]::OrdinalIgnoreCase) -ge 0)
}

function Unpair-WinRTDevice {
    param([string]$TargetName)
    try {
        $props = [System.Collections.Generic.List[string]]::new()
        $props.Add('System.ItemNameDisplay')
        $props.Add('System.Devices.Aep.IsPaired')

        # Query cached paired AssociationEndpoints instantly (<100ms) with IssueInquiry:=False instead of active inquiry scan
        $aqs = [Windows.Devices.Bluetooth.BluetoothDevice]::GetDeviceSelectorFromPairingState($true)
        $devices = Await-WinRTOperation ([Windows.Devices.Enumeration.DeviceInformation]::FindAllAsync($aqs, $props, [Windows.Devices.Enumeration.DeviceInformationKind]::AssociationEndpoint)) ([Windows.Devices.Enumeration.DeviceInformationCollection])

        $found = $false
        foreach ($device in $devices) {
            if (Test-TargetDevice $device.Name $TargetName) {
                $found = $true
                Write-Host "Unpairing stale device: $($device.Name) ($($device.Id))"
                $result = Await-WinRTOperation $device.Pairing.UnpairAsync() ([Windows.Devices.Enumeration.DeviceUnpairingResult])
                Write-Host "Unpair status: $($result.Status)"
            }
        }
        if (-not $found) {
            Write-Host "No paired profile found for '$TargetName' (already clean)."
        }
        return $true
    } catch {
        Write-Host "Error during unpair: $($_.Exception.Message)"
        return $false
    }
}

function Pair-WinRTDevice {
    param([string]$TargetName, [int]$TimeoutSeconds)
    try {
        Write-Host "Scanning for Bluetooth Mouse M336/M337/M535 in pairing mode (Timeout: ${TimeoutSeconds}s)..."
        [BluetoothSwitcherHelper]::Reset($TargetName)

        $props = [System.Collections.Generic.List[string]]::new()
        $props.Add('System.ItemNameDisplay')
        $props.Add('System.Devices.Aep.DeviceAddress')
        $props.Add('System.Devices.Aep.IsPaired')

        # AQS selector watching for unpaired Bluetooth devices or active inquiry responses
        $aqs = 'System.Devices.Aep.ProtocolId:="{e0cbf06c-cd8b-4647-bb8a-263b43f0f974}" AND (System.Devices.Aep.IsPaired:=System.StructuredQueryType.Boolean#False OR System.Devices.Aep.Bluetooth.IssueInquiry:=System.StructuredQueryType.Boolean#True)'
        $watcher = [Windows.Devices.Enumeration.DeviceInformation]::CreateWatcher(
            $aqs,
            $props,
            [Windows.Devices.Enumeration.DeviceInformationKind]::AssociationEndpoint
        )

        $addedHandlerType = [Windows.Foundation.TypedEventHandler[Windows.Devices.Enumeration.DeviceWatcher, Windows.Devices.Enumeration.DeviceInformation]]
        $addedDelegate = [Delegate]::CreateDelegate($addedHandlerType, [BluetoothSwitcherHelper].GetMethod("OnDeviceAdded"))

        $updatedHandlerType = [Windows.Foundation.TypedEventHandler[Windows.Devices.Enumeration.DeviceWatcher, Windows.Devices.Enumeration.DeviceInformationUpdate]]
        $updatedDelegate = [Delegate]::CreateDelegate($updatedHandlerType, [BluetoothSwitcherHelper].GetMethod("OnDeviceUpdated"))

        $tokenAdded = $watcher.add_Added($addedDelegate)
        $tokenUpdated = $watcher.add_Updated($updatedDelegate)

        $watcher.Start()

        $found = [BluetoothSwitcherHelper]::DeviceFoundEvent.WaitOne([TimeSpan]::FromSeconds($TimeoutSeconds))

        $watcher.Stop()
        $watcher.remove_Added($tokenAdded)
        $watcher.remove_Updated($tokenUpdated)

        $foundDevice = [BluetoothSwitcherHelper]::TargetDevice

        if (-not $found -or ($null -eq $foundDevice)) {
            Write-Host "Device not found within $TimeoutSeconds seconds."
            Write-Host "Make sure the mouse is in pairing mode (press the Bluetooth button underneath so the blue LED is blinking fast)." -ForegroundColor Yellow
            return $false
        }

        Write-Host "Found device: $($foundDevice.Name). Pairing..."
        
        # Setup custom pairing handler for PIN / Just Works confirmation
        $customPairing = $foundDevice.Pairing.Custom
        $pairHandlerType = [Windows.Foundation.TypedEventHandler[Windows.Devices.Enumeration.DeviceInformationCustomPairing, Windows.Devices.Enumeration.DevicePairingRequestedEventArgs]]
        $pairDelegate = [Delegate]::CreateDelegate($pairHandlerType, [BluetoothSwitcherHelper].GetMethod("OnPairingRequested"))
        $tokenPairing = $customPairing.add_PairingRequested($pairDelegate)

        try {
            $kinds = [Windows.Devices.Enumeration.DevicePairingKinds]::ConfirmOnly -bor [Windows.Devices.Enumeration.DevicePairingKinds]::ProvidePin
            $pairResult = Await-WinRTOperation ($customPairing.PairAsync($kinds)) ([Windows.Devices.Enumeration.DevicePairingResult])
            Write-Host "Custom pairing result: $($pairResult.Status)"

            if ($pairResult.Status -in @("Paired", "AlreadyPaired")) {
                return $true
            }
        } finally {
            $customPairing.remove_PairingRequested($tokenPairing)
        }

        # Fallback to standard PairAsync if custom pairing didn't succeed
        Write-Host "Attempting standard pairing..."
        $stdPairResult = Await-WinRTOperation ($foundDevice.Pairing.PairAsync()) ([Windows.Devices.Enumeration.DevicePairingResult])
        Write-Host "Standard pairing result: $($stdPairResult.Status)"
        return $stdPairResult.Status -in @("Paired", "AlreadyPaired")
    } catch {
        Write-Host "Error during pairing: $($_.Exception.Message)"
        return $false
    }
}

function Invoke-WinRTSwitch {
    Show-Notification "Switching Mouse to Windows" "Searching for Bluetooth Mouse M336/M337/M535... Press pairing button on mouse."
    
    # Unpair
    Unpair-WinRTDevice $DeviceName | Out-Null
    Start-Sleep -Milliseconds 800

    # Pair
    $success = Pair-WinRTDevice $DeviceName $TimeoutSeconds
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
    
    # 1. Unpair known and configured names
    foreach ($name in @("Bluetooth Mouse M336/M337/M535", $DeviceName)) {
        & btpair -u -n $name 2>$null | Out-Null
    }
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
        Initialize-WinRT; Invoke-WinRTSwitch
    }
} else {
    try {
        Initialize-WinRT; Invoke-WinRTSwitch
    } catch {
        Write-Error "Failed to initialize WinRT Bluetooth: $_"
        Write-Host "Tip: You can also install Bluetooth Command Line Tools (btpair) from https://bluetoothinstaller.com" -ForegroundColor Yellow
    }
}
