<#
.SYNOPSIS
    Connects the local iSCSI initiator to one or more iSCSI target portals.

.DESCRIPTION
    This script configures iSCSI target portals and establishes sessions from the local initiator 
    to multiple target portal IP addresses, optionally with multipath and session persistence. 
    It generates target addresses by incrementing the last octet of a given base IP.

.PARAMETER FirstTargetPortalAddress
    The base IP address of the first iSCSI target portal. 
    Example: 10.209.88.4

.PARAMETER Number_of_cnodes
    The number of iSCSI target nodes (CNODES) to connect to. 
    Each node IP is calculated by incrementing the last octet. Default is 2.

.PARAMETER NumOfSessionsPerTargetPortalAddress
    The number of iSCSI sessions to create per target portal address. Default is 1.

.EXAMPLE
    .\Connect-iSCSITargets.ps1 -FirstTargetPortalAddress "10.209.88.4"

.EXAMPLE
    .\Connect-iSCSITargets.ps1 -FirstTargetPortalAddress "10.209.88.4" -Number_of_cnodes 4 -NumOfSessionsPerTargetPortalAddress 2

.NOTES
    Author: David Turchak
    Date: 2025-05-28
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, HelpMessage = "The base IP address of the first iSCSI target portal. Example: 10.209.88.4")]
    [string]$FirstTargetPortalAddress,

    [Parameter(HelpMessage = "The number of iSCSI target nodes (CNODES) to connect to. Default is 2.")]
    [int]$Number_of_cnodes = 2,

    [Parameter(HelpMessage = "The number of iSCSI sessions per target portal address. Default is 1.")]
    [int]$NumOfSessionsPerTargetPortalAddress = 1
)

function Get-LocaliSCSIAddress {
    <#
    .SYNOPSIS
        Retrieves the local IPv4 address used for iSCSI communication.

    .DESCRIPTION
        Excludes the loopback interface and returns the IPv4 address 
        with the highest last octet, assuming it is the primary interface.
    #>

    $networkInterfaces = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -ne 'Loopback Pseudo-Interface 1' }
    $sortedInterfaces = $networkInterfaces | Sort-Object { [int]$_.IPAddress.Split('.')[-1] } -Descending
    return $sortedInterfaces[0].IPAddress
}

$LocaliSCSIAddress = Get-LocaliSCSIAddress

$TargetPortalAddresses = @()
$baseIP = $FirstTargetPortalAddress.Substring(0, $FirstTargetPortalAddress.LastIndexOf("."))
$lastOctet = [int]$FirstTargetPortalAddress.Substring($FirstTargetPortalAddress.LastIndexOf(".") + 1)
for ($i = 0; $i -lt $Number_of_cnodes; $i++) {
    $TargetPortalAddresses += "$baseIP.$($lastOctet + $i)"
}

foreach ($TargetPortalAddress in $TargetPortalAddresses) {
    Write-Host "Adding target portal for: $TargetPortalAddress"
    New-IscsiTargetPortal -TargetPortalAddress $TargetPortalAddress -InitiatorPortalAddress $LocaliSCSIAddress 
}

$NodeAddres = Get-IscsiTarget | Where-Object { -not $_.IsConnected } | Select-Object -ExpandProperty NodeAddress

1..$NumOfSessionsPerTargetPortalAddress | ForEach-Object {
    foreach ($TargetPortalAddress in $TargetPortalAddresses) {
        Connect-IscsiTarget -IsMultipathEnabled $true `
                            -TargetPortalAddress $TargetPortalAddress `
                            -InitiatorPortalAddress $LocaliSCSIAddress `
                            -IsPersistent $true `
                            -NodeAddress $NodeAddres
    }
}
