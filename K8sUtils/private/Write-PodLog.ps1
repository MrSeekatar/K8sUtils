function Write-PodLog {
    param (
        [Parameter(Mandatory)]
        [string] $PodName,
        [Parameter(Mandatory)]
        [string] $Prefix,
        [switch] $HasInit,
        [string] $Namespace = "default",
        [string] $Since,
        [ValidateSet("error", "warning", "ok","normal")]
        [string] $LogLevel = "ok",
        [string] $LogFileFolder
    )
    $extraLogParams = @()
    $logFilename = $null

    $msg = "Logs for $prefix $PodName"
    if ($Since) {
        $msg += " since ${Since}"
        $extraLogParams += "--since=$logSeconds"
    }
    if ($HasInit) {
        $extraLogParams = "--prefix", "--all-containers"
    }

    Write-Header $msg -LogLevel $LogLevel
    $tempFile = Get-TempLogFile
    if ($LogFileFolder) {
        Start-Transcript -Path $tempFile -UseMinimalHeader | Out-Null
    }
    kubectl logs --namespace $Namespace $PodName $extraLogParams 2>&1 |
        Where-Object { $_ -NotMatch 'Error.*: (PodInitializing|ContainerCreating)' } | Write-Plain
    if ($LogFileFolder) {
        Stop-Transcript | Out-Null
        $logFilename = Join-Path $LogFileFolder "$PodName.log"
        $end = $false
        # filter out the transcript header and footer
        Get-Content $tempFile | Select-Object -Skip 4 | ForEach-Object {
            if ($end -or $_ -eq '**********************') { $end = $true } else { $_ }
        } | Set-Content $logFilename
        Remove-Item $tempFile -ErrorAction SilentlyContinue
    }
    $getLogsExitCode = $LASTEXITCODE
    Write-Footer "End logs for $prefix $PodName"

    if ($getLogsExitCode -ne 0) {
        $msg = "Error getting logs for pod $PodName (exit = $getLogsExitCode), checking status"
        # TODO if you have multiple containers, this returns multiple chunks of json, but not in an array
        Write-Verbose "kubectl get pod $PodName -o jsonpath='{.status.containerStatuses.*.state}'"
        $state = ,(kubectl get pod $PodName -o jsonpath="{.status.containerStatuses.*.state}" | ConvertFrom-Json -Depth 5)
        foreach ($s in $state) {
            # can have running, waiting, or terminated properties
            if ($s -and (Get-Member -InputObject $s -Name waiting) -and (Get-Member -InputObject $s.waiting -Name reason)) {
                Write-Header $msg -LogLevel warning
                # waiting can have reason, message
                if ($s.waiting.reason -eq 'ContainerCreating') {
                    Write-Status "Pod is in ContainerCreating"
                } else {
                    Write-Status "Pod is waiting" -LogLevel error
                    Write-Status ($s.waiting | Out-String -Width 500) -LogLevel error
                }
            } elseif ($s -and (Get-Member -InputObject $s -Name terminated) -and (Get-Member -InputObject $s.terminated -Name reason)) {
                # terminated can have containerID, exitCode, finishedAt, reason, message, signal, startedAt
                Write-Header $msg -LogLevel error
                Write-Status "Pod was terminated" -LogLevel error
                Write-Status ($s.terminated | Out-String -Width 500) -LogLevel error
            } else {
                Write-Header $msg -LogLevel error
                Write-Warning "Didn't get known state:"
                Write-Warning ($s | Out-String)
            }
        }
    }
    return $logFilename
}