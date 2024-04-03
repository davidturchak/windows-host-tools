param (
    [string]$FirstTargetPortalAddress,
    [int]$Number_of_cnodes = 2,
    [int]$NumOfSessionsPerTargetPortalAddress = 1
)

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

# Increment the last octet of the first TargetPortalAddress to create an array of IP addresses
$TargetPortalAddresses = @()
$baseIP = $FirstTargetPortalAddress.Substring(0, $FirstTargetPortalAddress.LastIndexOf("."))
$lastOctet = [int]$FirstTargetPortalAddress.Substring($FirstTargetPortalAddress.LastIndexOf(".") + 1)
for ($i = 0; $i -lt $Number_of_cnodes; $i++) {
    $TargetPortalAddresses += "$baseIP.$($lastOctet + $i)"
}

# Configures an iSCSI target portal.
foreach ($TargetPortalAddress in $TargetPortalAddresses) {
   Write-Host "Adding target portal for: $TargetPortalAddress"
   New-IscsiTargetPortal -TargetPortalAddress $TargetPortalAddress # -TargetPortalPortNumber 3260 -InitiatorPortalAddress $LocaliSCSIAddress
}

$NodeAddres = Get-IscsiTarget

# Establishes a connection between the local iSCSI initiator and an iSCSI target device.
1..$NumOfSessionsPerTargetPortalAddress | ForEach-Object {
    foreach ($TargetPortalAddress in $TargetPortalAddresses) {
        Connect-IscsiTarget -IsMultipathEnabled $true -TargetPortalAddress $TargetPortalAddress -InitiatorPortalAddress $LocaliSCSIAddress -IsPersistent $true -NodeAddress $NodeAddres.NodeAddress
    }
}
