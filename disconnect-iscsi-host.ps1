<#
.SYNOPSIS
Disconnects iSCSI sessions and removes iSCSI target portals, optionally filtered by a specific Target Portal IP.

.DESCRIPTION
This script disconnects all iSCSI sessions and removes associated iSCSI target portals on the local machine.
If a specific TargetPortalIP is provided, only sessions and portals matching that IP are processed.

.PARAMETER TargetPortalIP
Optional. Specifies the IP address of the iSCSI target portal to filter connections and portals. 
If not provided, all iSCSI sessions and portals will be processed.

.EXAMPLE
.\Remove-iSCSISessions.ps1
Disconnects and removes all iSCSI sessions and portals.

.EXAMPLE
.\Remove-iSCSISessions.ps1 -TargetPortalIP "192.168.1.100"
Disconnects and removes only the iSCSI sessions and portals associated with the specified target portal IP.

.NOTES
Author: David Tuchak
Date: 2025-05-28
Requires: PowerShell 5.1 or later, administrative privileges, MSiSCSI service
#>

param (
    [Parameter(Mandatory=$false)]
    [string]$TargetPortalIP
)
# Get the list of iSCSI sessions
if ($TargetPortalIP) {
    Write-Host "Filtering for TargetPortalIP: $TargetPortalIP"
    # Get connections matching the specified TargetPortal
    $iSCSIConnections = Get-IscsiConnection | Where-Object { $_.TargetAddress -eq $TargetPortalIP }
    if ($null -eq $iSCSIConnections) {
        Write-Host "No iSCSI connections found for TargetPortalIP: $TargetPortalIP"
        $iSCSISessions = @()
    } else {
        Write-Host "Found $($iSCSIConnections.Count) connections for TargetPortal: $TargetPortalIP"
        # Get associated sessions for each connection
        $iSCSISessions = @()
        foreach ($connection in $iSCSIConnections) {
            try {
                $session = Get-CimAssociatedInstance -InputObject $connection -ResultClassName "MSFT_iSCSISession" -ErrorAction Stop
                if ($session) {
                    $iSCSISessions += $session | Select-Object -Property SessionIdentifier
                    Write-Host "Found session $($session.SessionIdentifier) for connection $($connection.ConnectionIdentifier)"
                }
            } catch {
                Write-Host "Error retrieving session for connection $($connection.ConnectionIdentifier): $_"
            }
        }
        if ($iSCSISessions.Count -eq 0) {
            Write-Host "No iSCSI sessions found for TargetPortalIP: $TargetPortalIP"
        }
    }
} else {
    # Get all sessions if no TargetPortal is specified
    $iSCSISessions = Get-IscsiSession | Select-Object -Property SessionIdentifier
    if ($null -eq $iSCSISessions) {
        Write-Host "No iSCSI sessions found."
    } else {
        Write-Host "Found $($iSCSISessions.Count) iSCSI sessions."
    }
}


# Run over them
foreach ($iSCSISession in $iSCSISessions)
{
Disconnect-IscsiTarget -SessionIdentifier $iSCSISession.SessionIdentifier -confirm:$false -ErrorAction SilentlyContinue
write-host "removed session $($iSCSISession.SessionIdentifier)"
start-sleep 1
}

# Get the list of iSCSI target portals
$targetPortals = Get-IscsiTargetPortal

# Get iSCSI target portals
if ($TargetPortalIP) {
    # Filter for the specified TargetPortal
    $targetPortals = Get-IscsiTargetPortal | Where-Object { $_.TargetPortalAddress -eq $TargetPortalIP }
} else {
    # Get all target portals if no TargetPortal is specified
    $targetPortals = Get-IscsiTargetPortal
}


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
