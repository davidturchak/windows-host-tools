param (
    [string]$filePath
)

# Convert file path to the directory portion
try {
    $directoryPath = (Get-Item -Path $filePath).DirectoryName
} catch {
    Write-Host "Error: Invalid file path provided."
    exit
}

# Ensure directory path is not null or empty
if (-not $directoryPath) {
    Write-Host "Error: The provided path does not have a parent directory (it may be a root drive)."
    exit
}

# Query WMI for volumes
$volumes = Get-WmiObject -Query "SELECT * FROM Win32_Volume"

# Check each directory in the hierarchy
function Is-MountPoint($path) {
    foreach ($volume in $volumes) {
        # Ensure it's not just a drive letter (root), unless it's mounted separately
        if (($volume.Name.TrimEnd('\') -eq $path.TrimEnd('\')) -and ($volume.DriveType -ne 3)) {
            return $true
        }
    }

    # Check if the directory is a reparse point (symbolic link, junction, etc.)
    try {
        $item = Get-Item $path
        if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            return $true
        }
    } catch {
        # In case the directory doesn't exist or cannot be accessed
        return $false
    }

    return $false
}

$currentPath = $directoryPath

while ($currentPath -and $currentPath -ne (Split-Path $currentPath -Parent)) {
    if (Is-MountPoint $currentPath) {
        
        $partition = Get-Partition | Where-Object { $_.AccessPaths -contains $currentPath + '\'}
        $disk = Get-Disk | Where-Object { $_.Number -eq $partition.DiskNumber }
        $manuf = $disk.FriendlyName
        $serial = $disk.SerialNumber
        Write-Host "The path '$currentPath' is a mount point to '$manuf' with Serial Number: '$serial'"

        break
    }
    $parentPath = Split-Path $currentPath -Parent
    # Check if the parent path is not empty to avoid calling Split-Path on an empty string
    if ($parentPath -and $parentPath -ne $currentPath) {
        $currentPath = $parentPath
    } else {
        break
    }
}

if (-not (Is-MountPoint $currentPath)) {
    $driveLetter = (Split-Path -Path $filePath -Qualifier).TrimEnd(':')
    $partition = Get-Partition | Where-Object { $_.DriveLetter -eq $driveLetter }
    $disk = Get-Disk | Where-Object { $_.Number -eq $partition.DiskNumber }
    $manuf = $disk.FriendlyName
    $serial = $disk.SerialNumber
    Write-Host "No mount point found for the path '$filePath'. But '$driveLetter' is pointing to '$manuf' with Serial Number: '$serial'"
}
