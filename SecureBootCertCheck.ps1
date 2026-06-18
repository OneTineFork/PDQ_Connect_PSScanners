# 1. Determine Firmware Type (Legacy BIOS vs UEFI)
$csObj = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue 2>$null
$FirmwareType = if ($csObj) { $csObj.FirmwareType } else { $null }

# 2. Determine Secure Boot State safely using inline conditions
$SecureBootState = if ($FirmwareType -eq 1) {
    "Legacy BIOS"
} else {
    # Check actual Secure Boot status via the environment or registry if UEFI
    $sbStateObj = Get-CimInstance -Namespace root\Microsoft\Windows\SecureBoot -ClassName MSFT_SecureBoot -ErrorAction SilentlyContinue 2>$null
    if ($sbStateObj) {
        if ($sbStateObj.SecureBoot) { "Enabled" } else { "Disabled" }
    } else {
        # Fallback check if the WMI class isn't populated but it is UEFI
        $sbReg = Get-ItemPropertyValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State" -Name "UEFISecureBootEnabled" -ErrorAction SilentlyContinue 2>$null
        if ($sbReg -eq 1) { "Enabled" } elseif ($sbReg -eq 0) { "Disabled" } else { "Unsupported/Unknown" }
    }
}

# 3. Check UEFI db Certificate (Only run if Secure Boot is an actively supported feature state)
$IsSecureBootSupported = if ($SecureBootState -eq "Enabled" -or $SecureBootState -eq "Disabled") { $true } else { $false }

$dbObj = if ($IsSecureBootSupported) { Get-SecureBootUEFI -Name db -ErrorAction SilentlyContinue 2>$null } else { $null }
$DB = if ($dbObj) { [System.Text.Encoding]::ASCII.GetString($dbObj.Bytes) -match 'Windows UEFI CA 2023' } else { $false }

# 4. Check UEFI KEK Certificate (Only run if Secure Boot is an actively supported feature state)
$kekObj = if ($IsSecureBootSupported) { Get-SecureBootUEFI -Name KEK -ErrorAction SilentlyContinue 2>$null } else { $null }
$KEK = if ($kekObj) { [System.Text.Encoding]::ASCII.GetString($kekObj.Bytes) -match 'KEK 2K CA 2023' } else { $false }

# 5. Verify Registry Path Existence and Safe Value Retrieval
$regPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\Servicing'
$regKey = Get-Item -Path $regPath -ErrorAction SilentlyContinue

# Extract value names safely if the key exists
$availableValues = if ($regKey) { $regKey.GetValueNames() } else { @() }

# 6. Fetch Registry Values safely by confirming existence first
$UEFICA2023Status = if ($availableValues -contains 'UEFICA2023Status') { Get-ItemPropertyValue -Path $regPath -Name 'UEFICA2023Status' -ErrorAction SilentlyContinue 2>$null } else { $null }
$UEFICA2023Error  = if ($availableValues -contains 'UEFICA2023Error')  { Get-ItemPropertyValue -Path $regPath -Name 'UEFICA2023Error'  -ErrorAction SilentlyContinue 2>$null } else { $null }

# 7. Get Last Boot Time
$osObj = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue 2>$null
$LastBoot = if ($osObj) { $osObj.LastBootUpTime } else { $null }

# 8. Output Results
[PSCustomObject]@{
    SecureBootState   = $SecureBootState
    DB                = $DB
    KEK               = $KEK
    UEFICA2023Status  = $UEFICA2023Status
    UEFICA2023Error   = $UEFICA2023Error
    LastBoot          = $LastBoot
}