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

# Loop through each target portal and remove it
foreach ($portal in $targetPortals) {
    try {
        Remove-IscsiTargetPortal -TargetPortalAddress $portal.TargetPortalAddress -confirm:$false -ErrorAction Stop
        Write-Host "Removed target portal: $($portal.TargetPortalAddress)"
    } catch {
        Write-Host "Error removing target portal $($portal.TargetPortalAddress): $_"
    }
}
# Restart iscsi service 
Restart-Service -Name MSiSCSI

Write-Host "All target portals have been processed."
