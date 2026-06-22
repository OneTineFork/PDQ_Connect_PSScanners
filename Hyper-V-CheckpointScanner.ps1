# 1. Locate the correct Hyper-V directory on D:
$targetDir = Get-Item -Path "D:\Hyper*" -ErrorAction SilentlyContinue | 
             Where-Object { $_.PSIsContainer -and ($_.Name -eq "Hyper-V" -or $_.Name -eq "HyperV") } | 
             Select-Object -First 1 -ExpandProperty FullName

# Initialize output object properties
$result = [ordered]@{
    HyperVDirectoryFound = $false
    UnmergedFilesCount   = 0
    LargestAvhdxSizeGB   = 0.00
    OrphanedFilesCount   = 0
    OrphanedFileList     = "None"
}

if ($targetDir) {
    $result.HyperVDirectoryFound = $true

    # 2. Gather all .avhdx files in the directory
    $avhdxFiles = Get-ChildItem -Path $targetDir -Filter "*.avhdx" -Recurse -ErrorAction SilentlyContinue

    if ($avhdxFiles) {
        $result.UnmergedFilesCount = $avhdxFiles.Count
        
        # Calculate largest file size in GB
        $maxSize = ($avhdxFiles | Measure-Object -Property Length -Maximum).Maximum
        if ($maxSize) {
            $result.LargestAvhdxSizeGB = [math]::Round($maxSize / 1GB, 2)
        }

        # 3. Check for orphaned checkpoints
        if (Get-Module -ListAvailable -Name Hyper-V) {
            
            # Gather paths from base VMs
            $vmPaths = Get-VM | Get-VMHardDiskDrive | Select-Object -ExpandProperty Path

            # Gather paths explicitly attached to any existing snapshots
            $snapshotPaths = Get-VM | Get-VMSnapshot | Get-VMHardDiskDrive | Select-Object -ExpandProperty Path

            # Combine them into a unique list of all active files known to Hyper-V
            $activeHyperVPaths = ($vmPaths + $snapshotPaths) | Select-Object -Unique

            # Filter for avhdx files on disk that are NOT in Hyper-V's active inventory
            $orphanedFiles = $avhdxFiles | Where-Object {
                $filePath = $_.FullName
                $filePath -notin $activeHyperVPaths
            }

            if ($orphanedFiles) {
                $result.OrphanedFilesCount = $orphanedFiles.Count
                $result.OrphanedFileList = ($orphanedFiles.Name) -join ", "
            }
        } else {
            $result.OrphanedFileList = "Error: Hyper-V PowerShell module missing"
        }
    }
}

# Output the single object for PDQ Connect
[PSCustomObject]$result