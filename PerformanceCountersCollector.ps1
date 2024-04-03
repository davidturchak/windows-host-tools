function Start-PerformanceCountersCollection {
    param (
        [string[]]$DriveLetters,
        [int]$SampleIntervalInSeconds = 1,
        [int]$DurationInSeconds = 60
    )

    $dateStamp = Get-Date -Format "yyyyMMdd_HHmmss"

    foreach ($driveLetter in $DriveLetters) {
        $logFileName = "Drive_${driveLetter}_PerfCounters_${dateStamp}.blg"
        $logFilePath = Join-Path -Path $env:TEMP -ChildPath $logFileName

        $counterPath = "\\$env:COMPUTERNAME\LogicalDisk($driveLetter`:)\Disk Writes/sec"
        $counter = Get-Counter -Counter $counterPath -ErrorAction SilentlyContinue

        if ($null -eq $counter) {
            Write-Host "The counter '$counterPath' was not found. Please check the counter path and try again."
            return
        }

        $startDateTime = Get-Date
        $endDateTime = $startDateTime.AddSeconds($DurationInSeconds)

        $counterSet = @()
        while ((Get-Date) -lt $endDateTime) {
            $counterValue = (Get-Counter -Counter $counterPath).CounterSamples[0].CookedValue
            $counterSet += New-Object PSObject -Property @{
                "TimeStamp" = (Get-Date)
                "Drive" = $driveLetter
                "DiskWritesPerSec" = $counterValue
            }
            Start-Sleep -Seconds $SampleIntervalInSeconds
        }

        $counterSet | Export-Csv -Path $logFilePath -NoTypeInformation
        Write-Host "Performance counters collection for drive '$driveLetter' completed."
        Write-Host "Log file path: $logFilePath"
    }
}

# Usage example:
$driveLetters = @("C")  # Add the drive letters you want to monitor here
Start-PerformanceCountersCollection -DriveLetters $driveLetters -SampleIntervalInSeconds 1 -DurationInSeconds 10
