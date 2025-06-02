<#
.SYNOPSIS
Helper to get and write pod logs with header and footer

.PARAMETER PodName
Name of the pod to get logs for

.PARAMETER Prefix
Prefix for the log header

.PARAMETER HasInit
Set to true if the pod has an init container

.PARAMETER Namespace
K8s namespace to use, defaults to default

.PARAMETER Since
If specified, only get logs since this time (e.g. 1h, 2m, 30s)

.PARAMETER LogLevel
Log level to use for the header, defaults to ok

.PARAMETER LogFileFolder
Optional folder to write the logs to

.EXAMPLE
An example

.NOTES
General notes
#>
function Write-PodLog {
    [CmdletBinding()]
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
    # get the pod status to see if we should look at
    $podJson = kubectl get pod $PodName --namespace $Namespace -o json
    $podStatus =  $podJson | ConvertFrom-Json -Depth 100
    if ($LASTEXITCODE -ne 0) {
        $extraLogParams += "--previous"
        $LASTEXITCODE = 0
    } elseif ($podStatus.status.containerStatuses.restartCount -gt 0) {
        $extraLogParams += "--previous"
    }

    Write-Verbose ($podJson | Out-String)
    Write-Verbose "kubectl logs --namespace $Namespace $PodName $($extraLogParams -join ' ')"
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
                if ($msg) { Write-Header $msg -LogLevel warning; $msg = $null }
                # waiting can have reason, message
                if ($s.waiting.reason -eq 'ContainerCreating') {
                    Write-Status "Pod is in ContainerCreating"
                } else {
                    Write-Status "Pod is waiting" -LogLevel error
                    Write-Status ($s.waiting | Out-String -Width 500) -LogLevel error
                }
            } elseif ($s -and (Get-Member -InputObject $s -Name terminated) -and (Get-Member -InputObject $s.terminated -Name reason)) {
                # terminated can have containerID, exitCode, finishedAt, reason, message, signal, startedAt
                if ($msg) { Write-Header $msg -LogLevel error; $msg = $null }
                Write-Status "Pod was terminated" -LogLevel error
                Write-Status ($s.terminated | Out-String -Width 500) -LogLevel error
            } else {
                if ($msg) { Write-Header $msg -LogLevel error; $msg = $null }
                Write-Warning "Didn't get known state:"
                Write-Warning ($s | Out-String)
            }
        }
        Write-Footer
    }
    return $logFilename
}