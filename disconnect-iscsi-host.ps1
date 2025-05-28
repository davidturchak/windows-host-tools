# Get the list of iscsi sessions
$iSCSISessions = Get-iSCSISession | Select-Object SessionIdentifier

# Run over them
foreach ($iSCSISession in $iSCSISessions)
{
Disconnect-IscsiTarget -SessionIdentifier $iSCSISession.SessionIdentifier -confirm:$false -ErrorAction SilentlyContinue
write-host "removed session $($iSCSISession.SessionIdentifier)"
start-sleep 1
}

# Get the list of iSCSI target portals
$targetPortals = Get-IscsiTargetPortal

function Get-LocaliSCSIAddress {
    # Get all IPv4 addresses of network interfaces excluding loopback
    $networkInterfaces = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -ne 'Loopback Pseudo-Interface 1' }

    # Sort network interfaces by the last octet of their IPv4 addresses
    $sortedInterfaces = $networkInterfaces | Sort-Object { [int]$_.IPAddress.Split('.')[-1] } -Descending

    # Select the first interface from the sorted list
    $LocaliSCSIAddress = $sortedInterfaces[0].IPAddress

    return $LocaliSCSIAddress
}


# Get the local iSCSI address
$LocaliSCSIAddress = Get-LocaliSCSIAddress

# Loop through each target portal and remove it
foreach ($portal in $targetPortals) {
    try {
        Remove-IscsiTargetPortal -TargetPortalAddress $portal.TargetPortalAddress -InitiatorPortalAddress $LocaliSCSIAddress -confirm:$false -ErrorAction Stop
        Write-Host "Removed target portal: $($portal.TargetPortalAddress)"
    } catch {
        Write-Host "Error removing target portal $($portal.TargetPortalAddress): $_"
    }
}
# Restart iscsi service (optional) 
Restart-Service -Name MSiSCSI

Write-Host "All target portals have been processed."
