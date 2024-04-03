param (
    [Alias('n')]
    [string]$TestName = "",
    [Alias('r')]
    [string]$TestRuntime = "",
    [Alias('b')]
    [string]$bs = "",
    [Alias('s')]
    [int]$Step = 0,
    [Alias('j')]
    [int]$Jobs = 0,
    [Alias('e')]
    [int]$StopThread = 50,
    [Alias('t')]
    [int]$StartThread = 1,
    [Alias('i')]
    [string]$SdpIP = "",
    [Alias('p')]
    [string]$SdpPass = "",
    [switch]$Help
)

function Show-Help {
    Write-Output "Usage: ./script.ps1 [options]"
    Write-Output "Options:"
    Write-Output "  -n, --testname <name>       Test name (randread or randwrite)"
    Write-Output "  -r, --testruntime <time>    Test runtime"
    Write-Output "  -b, --bs <size>             Block size"
    Write-Output "  -s, --step <size>           Step size"
    Write-Output "  -j, --jobs <num>            Number of jobs"
    Write-Output "  -e, --stopthread <num>      Stop thread"
    Write-Output "  -t, --startthread <num>     Start thread"
    Write-Output "  -i, --sdpip <ip>            SDP IP address"
    Write-Output "  -p, --sdppass <password>    SDP password"
    Write-Output "  -h, --help                  Show help"
    exit 1
}

# Parse command line options
if ($Help) {
    Show-Help
}

# Check if required parameters are provided
if (-not $TestName -or -not $TestRuntime -or -not $bs -or -not $Step -or -not $Jobs -or -not $StopThread -or -not $StartThread -or -not $SdpIP -or -not $SdpPass) {
    Write-Output "$TestName -or -not $TestRuntime -or -not $bs -or -not $Step -or -not $Jobs -or -not $StopThread -or -not $StartThread -or -not $SdpIP -or -not $SdpPass"
    Write-Output "Missing required parameters."
    Show-Help
}

if ($TestName -ne "randread" -and $TestName -ne "randwrite") {
    Write-Output "Invalid TestName specified. Please provide 'randread' or 'randwrite'."
    exit 1
}

if ($PSVersionTable.PSEdition -eq 'Core') {
    Write-Output "Running in PowerShell 7 or later."
} else {
    Write-Output "ERROR: This script can run on Powershell 7 only. You running in Windows PowerShell (version $($PSVersionTable.PSVersion.Major))."
    exit 1
}

# Create a working folder for the test
$folderName = "${TestName}_${bs}k"
$relativePath = ".\$folderName"

if (Test-Path $relativePath) {
    $confirmation = Read-Host "The folder '$relativePath' already exists. Do you want to overwrite it? (Y/N)"
    if ($confirmation -ne "Y" -and $confirmation -ne "y") {
        Write-Output "Operation aborted. Folder will not be overwritten. Exiting script."
        exit 1
    }
    Remove-Item -Path $relativePath -Recurse
}

New-Item -ItemType Directory -Path $relativePath | Out-Null
$fullPath = Convert-Path $relativePath
Write-Output "Full path of the test run: $fullPath"

function Get-VM-Size {

    if (Get-CimInstance -ClassName Win32_SystemDriver | Where-Object { $_.DisplayName -match "HyperVideo" -and $_.State -match "running"}) {
        # Running on an Azure VM. Going to retrieve the VM size
        $vmSize = (Invoke-RestMethod -Uri "http://169.254.169.254/metadata/instance/compute/vmSize?api-version=2021-02-01&format=text" -Headers @{ Metadata = "true" })
    }
    elseif (Get-CimInstance -ClassName Win32_SystemDriver | Where-Object { $_.DisplayName -match "google" -and $_.State -match "running"}) {
        # Running on a GCP VM. Going to retrieve the VM shape
        $vmSize = (Invoke-RestMethod -Uri "http://metadata.google.internal/computeMetadata/v1/instance/machine-type" -Headers @{ "Metadata-Flavor" = "Google" })
        $vmSize = ($vmSize -split '/')[-1]
    }
    else {
        # Not running on an Azure or GCP VM. Going to use the CPU core count
        $vmSize = (Get-WmiObject Win32_ComputerSystem).NumberOfLogicalProcessors
    }
    return $vmSize
}



function Get-Sdp-Time {
    $sdpUri = "https://${SdpIP}/api/v2/system/state"
    $cred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList @("admin", (ConvertTo-SecureString -AsPlainText $SdpPass -Force))
    try {
        $response = Invoke-RestMethod -Uri $sdpUri -Credential $cred -Method Get -TimeoutSec 5 -SkipCertificateCheck
        $float_time = $response.hits[0].system_time
        $integer_time = [math]::Round($float_time)
        return $integer_time
    }
    catch {
        Write-Output "[ERROR]: Failed to retrieve time from SDP."
        exit 1
    }
}

function Get-Sdp-Disks {
    $SdpDiskDrives = Get-CimInstance -ClassName Win32_DiskDrive |
              Where-Object { $_.Model -match "KMNRIO|SILK" -and $_.SerialNumber -notmatch "0000" } |
              Select-Object -ExpandProperty Name
    # Join the disk names with ":"
    $sdpDrives = $SdpDiskDrives -join ":"

    if (-not $sdpDrives) {
            Write-Output "No SILK drives found. Exiting script."
            exit 1
        }
        return $sdpDrives
}

function Get-Sdp-Statistics {
    param (
        $SdpStart,
        $SdpEnd
    )
    $SummaryJson = "${relativePath}\${TestName}_${bs}k_SDPstart_${SdpStart}_SDPend_${SdpEnd}.json"
    $sdpUri = "https://${SdpIP}/api/v2/stats/system?__datapoints=1000&__pretty&__from_time=${SdpEnd}&__resolution=5s"
    $cred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList @("admin", (ConvertTo-SecureString -AsPlainText $SdpPass -Force))
    try {
        Invoke-RestMethod -Uri $sdpUri -Credential $cred -Method Get -TimeoutSec 5 -SkipCertificateCheck -OutFile $SummaryJson
        Write-Output "[INFO]: The SDP statistics file is $SummaryJson"
    }
    catch {
        Write-Output "[ERROR]: Failed to retrieve SDP statistics."
        exit 1
    }
}


$fioPath = Get-ChildItem -Path "C:\tools\fio" -Filter "fio.exe" -Recurse -File -ErrorAction SilentlyContinue
if (-not $fioPath) {
    Write-Output "The file 'fio' does not exist. Exiting script."
    exit 1
}

$SdpDisks = Get-Sdp-Disks
$SdpTestsStartTime = Get-Sdp-Time

for ($t = $StartThread; $t -le $StopThread; $t += $Step) {
    $SdpTestStartTime = Get-Sdp-Time
    & $fioPath `
        --filename=$SdpDisks `
        --direct=1 `
        --thread `
        --rw=$TestName `
        --numjobs=$Jobs `
        --buffer_compress_percentage=75 `
        --refill_buffers `
        --buffer_pattern=0xdeadbeef `
        --time_based `
        --group_reporting `
        --name="${TestName}-test-job-name" `
        --runtime="$TestRuntime" `
        --bs="${bs}k" `
        --iodepth=$t `
        --log_avg_msec=1000 `
        --write_lat_log="${relativePath}\fio_latency_histogram_${SdpTestStartTime}_${TestName}_${bs}k_threads_$t" `
        --write_iops_log="${relativePath}\fio_iops_histogram_${SdpTestStartTime}_${TestName}_${bs}k_threads_$t" `
        --write_bw_log="${relativePath}\fio_bw_histogram_${SdpTestStartTime}_${TestName}_${bs}k_threads_$t"
}

Write-Output "[INFO]: Going to extract statistics from SDP:"

$SdpTestsEndTime = Get-Sdp-Time
Get-Sdp-Statistics $SdpTestsStartTime $SdpTestsEndTime
Write-Output "SDP tests End Epoch Time: $SdpTestsEndTime"

$vmSize = Get-VM-Size

Compress-Archive -Path "${relativePath}\*" -DestinationPath "${relativePath}\${TestName}_CPU_${vmSize}_jobs${Jobs}_Start_${SdpTestsStartTime}_End_${SdpTestsEndTime}.zip" -Force
Remove-Item -Path "${relativePath}\*.log" -Force
Remove-Item -Path "${relativePath}\*.json" -Force

exit 0