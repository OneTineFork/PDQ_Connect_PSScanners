# Shadow Copy Configuration Scanner for PDQ Connect
# Returns one row per fixed local volume

# --- Helper: Safe registry read without try-catch ---
function Get-RegistryValue {
    param(
        [string]$Path,
        [string]$Name
    )
    if (Test-Path -Path $Path) {
        $item = Get-ItemProperty -Path $Path -ErrorAction SilentlyContinue
        if ($null -ne $item -and $null -ne $item.$Name) {
            return $item.$Name
        }
    }
    return $null
}

# --- Helper: Gather shadow copy scheduled tasks and exact schedules safely ---
function Get-ShadowCopyTasks {
    if (-not (Get-Module -ListAvailable -Name ScheduledTasks)) {
        return @()
    }

    $allTasks = Get-ScheduledTask -ErrorAction SilentlyContinue
    if (-not $allTasks) { return @() }

    $results = @()
    foreach ($task in $allTasks) {
        $matchFound = $false
        if ($task.TaskName -like '*ShadowCopy*') {
            $matchFound = $true
        } else {
            foreach ($action in $task.Actions) {
                if (($action.Execute -match 'vssadmin|wmic|powershell') -or ($action.Arguments -match 'shadow')) {
                    $matchFound = $true
                    break
                }
            }
        }

        if ($matchFound) {
            $triggers = $task.Triggers
            $scheduleStrings = @()

            if ($triggers) {
                foreach ($trigger in $triggers) {
                    if ($null -ne $trigger.Enabled -and -not $trigger.Enabled) { continue }

                    $type = $trigger.GetType().Name.Replace("CimInstance#Root/Microsoft/Windows/TaskScheduler/MSFT_", "")

                    $timeStr = ""
                    if ($trigger.StartBoundary -and $trigger.StartBoundary -match 'T(\d{2}:\d{2})') {
                        $timeStr = " at $($Matches[1])"
                    }

                    if ($type -match 'Daily') { $type = "Daily$timeStr" }
                    elseif ($type -match 'Weekly') { $type = "Weekly$timeStr" }
                    elseif ($type -match 'Time|Once') { $type = "One-time$timeStr" }
                    elseif ($type -match 'TaskTrigger') { $type = "Custom Trigger" }
                    else { $type = $type.Replace("Trigger", "") + $timeStr }

                    if ($type) { $scheduleStrings += $type }
                }
            }

            $results += [pscustomobject]@{
                TaskName  = $task.TaskName
                TaskPath  = $task.TaskPath
                Schedules = ($scheduleStrings | Select-Object -Unique)
            }
        }
    }
    return $results
}

# --- Helper: Parse vssadmin list shadowstorage output ---
function Get-VssShadowStorageMap {
    $map = @{}

    $vssadminPath = Join-Path $env:SystemRoot 'System32\vssadmin.exe'
    if (-not (Test-Path $vssadminPath)) {
        return $map
    }

    $raw = & $vssadminPath list shadowstorage 2>$null
    if (-not $raw) {
        return $map
    }

    $lines = @($raw | Where-Object { $_ -ne $null })

    $currentDrive = $null
    $used = $null
    $allocated = $null
    $maximum = $null

    function Save-CurrentVssBlock {
        param(
            [hashtable]$TargetMap,
            [string]$Drive,
            [string]$UsedValue,
            [string]$AllocatedValue,
            [string]$MaximumValue
        )

        if (-not [string]::IsNullOrWhiteSpace($Drive)) {
            $TargetMap[$Drive.ToUpper()] = [pscustomobject]@{
                Drive     = $Drive.ToUpper()
                Used      = if ($UsedValue) { $UsedValue } else { '0 Bytes' }
                Allocated = if ($AllocatedValue) { $AllocatedValue } else { '0 Bytes' }
                Maximum   = if ($MaximumValue) { $MaximumValue } else { 'Not Allocated' }
            }
        }
    }

    foreach ($line in $lines) {
        $trimmed = $line.Trim()

        if ($trimmed -match '^For volume:\s+.*\(([A-Z]:)\)') {
            if ($currentDrive) {
                Save-CurrentVssBlock -TargetMap $map -Drive $currentDrive -UsedValue $used -AllocatedValue $allocated -MaximumValue $maximum
            }

            $currentDrive = $Matches[1]
            $used = $null
            $allocated = $null
            $maximum = $null
            continue
        }

        if ($trimmed -match '^Used Shadow Copy Storage space:\s+(.+)$') {
            $used = $Matches[1].Trim()
            continue
        }

        if ($trimmed -match '^Allocated Shadow Copy Storage space:\s+(.+)$') {
            $allocated = $Matches[1].Trim()
            continue
        }

        if ($trimmed -match '^Maximum Shadow Copy Storage space:\s+(.+)$') {
            $maximum = $Matches[1].Trim()
            continue
        }
    }

    if ($currentDrive) {
        Save-CurrentVssBlock -TargetMap $map -Drive $currentDrive -UsedValue $used -AllocatedValue $allocated -MaximumValue $maximum
    }

    return $map
}

# --- Registry: MaxShadowCopies ---
$registryVal = Get-RegistryValue `
    -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\VSS\Settings' `
    -Name 'MaxShadowCopies'
$maxShadowCopies = if ($null -ne $registryVal) { $registryVal.ToString() } else { 'Default (64)' }

# --- Volumes: fixed local disks with drive letters ---
$volumes = Get-CimInstance Win32_Volume -ErrorAction SilentlyContinue | Where-Object {
    $_.DriveType -eq 3 -and $_.DriveLetter -match '^[A-Z]:$'
}

# --- Existing shadow copies ---
$copyLookup = @{}
$shadowCopies = Get-CimInstance Win32_ShadowCopy -ErrorAction SilentlyContinue
if ($shadowCopies) {
    foreach ($c in $shadowCopies) {
        if ($null -ne $c.VolumeName) {
            $key = ([string]$c.VolumeName).ToLower()
            if (-not $copyLookup.ContainsKey($key)) { $copyLookup[$key] = @() }
            $copyLookup[$key] += $c
        }
    }
}

# --- Scheduled tasks ---
$shadowTasks = Get-ShadowCopyTasks

# --- vssadmin shadow storage map ---
$vssStorageMap = Get-VssShadowStorageMap

# --- Build result set: one row per fixed volume ---
$results = @()

if ($volumes) {
    foreach ($v in ($volumes | Sort-Object DriveLetter)) {
        $volumeId = ([string]$v.DeviceID).ToLower()
        $drive    = $v.DriveLetter.ToUpper()
        $label    = $v.Label

        # Default Storage Metrics
        $maxStorageAllowed     = "Not Allocated"
        $allocatedShadowStorage = "Not Allocated"
        $shadowStorageUsed     = "0 Bytes"
        $hasStorage            = $false

        # Pull storage data from vssadmin output
        if ($vssStorageMap.ContainsKey($drive)) {
            $storage = $vssStorageMap[$drive]
            $hasStorage = $true

            if ($null -ne $storage.Maximum -and $storage.Maximum -ne '') {
                $maxStorageAllowed = $storage.Maximum
            }

            if ($null -ne $storage.Allocated -and $storage.Allocated -ne '') {
                $allocatedShadowStorage = $storage.Allocated
            }

            if ($null -ne $storage.Used -and $storage.Used -ne '') {
                $shadowStorageUsed = $storage.Used
            }
        }

        
	$hasCopies = $false
	$shadowCopyCount = 0
	$lastSuccess = 'N/A'

	if ($null -ne $volumeId -and $copyLookup.ContainsKey($volumeId)) { 
    $hasCopies = $true 
    
    $matchedCopies = $copyLookup[$volumeId]
    
    # Count
    $shadowCopyCount = $matchedCopies.Count
    
    # Last success
    $latest = $matchedCopies | Sort-Object InstallDate -Descending | Select-Object -First 1
    if ($latest -and $latest.InstallDate) {
        $lastSuccess = Get-Date ($latest.InstallDate) -Format "yyyy-MM-dd HH:mm:ss"
    }
}


        # Match tasks against this drive
        $matchingTasks = @()
        foreach ($task in $shadowTasks) {
            $nameMatchesDrive = $drive -and $task.TaskName -match [regex]::Escape($drive)
            $isGlobalTaskAndVolumeActive = ($task.TaskName -like "*ShadowCopy*") -and ($hasStorage -or $hasCopies)

            if ($nameMatchesDrive -or $isGlobalTaskAndVolumeActive) {
                $matchingTasks += $task
            }
        }

        $scheduleStrings = @()
        foreach ($mt in $matchingTasks) {
            if ($mt.Schedules) { $scheduleStrings += $mt.Schedules }
        }
        $scheduleStrings = $scheduleStrings | Where-Object { $_ } | Select-Object -Unique

        $enabled = $hasStorage -or $hasCopies

        
	$results += [pscustomobject]@{
		Drive                  = $drive
		Label                  = if ($label) { $label } else { '' }
		ShadowCopiesEnabled    = [bool]$enabled
		Schedule               = if ($scheduleStrings.Count -gt 0) { $scheduleStrings -join ' | ' } else { 'None' }
		MaxShadowCopies        = $maxShadowCopies
		MaxStorageAllowed      = $maxStorageAllowed
		AllocatedShadowStorage = $allocatedShadowStorage
		ShadowStorageUsed      = $shadowStorageUsed
		ShadowCopyCount        = $shadowCopyCount   # ← NEW
		LastSuccessTime        = $lastSuccess
	}

    }
}

# --- Return Statement strictly structured for PDQ Connect ---
if ($results.Count -eq 0) {
    [pscustomobject]@{
        Drive                  = 'N/A'
        Label                  = 'No Fixed Volumes Found'
        ShadowCopiesEnabled    = $false
        Schedule               = 'None'
        MaxShadowCopies        = $maxShadowCopies
        MaxStorageAllowed      = 'N/A'
        AllocatedShadowStorage = 'N/A'
        ShadowStorageUsed      = 'N/A'
        LastSuccessTime        = 'N/A'
		ShadowCopyCount 	   = 0
    }
} else {
    $results
}