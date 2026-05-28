# Attempt to gather disk reliability counters safely
$Results = Get-PhysicalDisk -ErrorAction SilentlyContinue |
    Get-StorageReliabilityCounter -ErrorAction SilentlyContinue |
    ForEach-Object {
        [PSCustomObject]@{
            DeviceId         = $_.DeviceId
            Wear             = $_.Wear
            ReadErrorsTotal  = $_.ReadErrorsTotal
            WriteErrorsTotal = $_.WriteErrorsTotal
            Status           = 'Success'
        }
    }

# Output results if found
if ($Results) {
    $Results
} 
else {
    # If no results, determine if it's a missing feature (like on a VM/Older OS) or just no data
    if (Get-Command Get-PhysicalDisk -ErrorAction SilentlyContinue) {
        $StatusMessage = 'No reliability data available for these drives (Common on Virtual Machines).'
    } else {
        $StatusMessage = 'Error: Storage cmdlets are not supported or available on this OS version.'
    }

    # Fallback object matching the exact same schema
    [PSCustomObject]@{
        DeviceId         = 'N/A'
        Wear             = 0
        ReadErrorsTotal  = 0
        WriteErrorsTotal = 0
        Status           = $StatusMessage
    }
}
