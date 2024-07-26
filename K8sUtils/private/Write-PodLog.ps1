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
        [string] $LogLevel = "ok"
    )
    $extraLogParams = @()

    $msg = "Logs for $prefix $PodName"
    if ($Since) {
        $msg += " since ${Since}"
        $extraLogParams += "--since=$logSeconds"
    }
    if ($HasInit) {
        $extraLogParams = "--prefix", "--all-containers"
    }

    Write-Header $msg -LogLevel $LogLevel
    kubectl logs --namespace $Namespace $PodName $extraLogParams 2>&1 |
        Where-Object { $_ -NotMatch 'Error.*: (PodInitializing|ContainerCreating)' } | Write-Plain
    $getLogsExitCode = $LASTEXITCODE
    Write-Footer "End logs for $prefix $PodName"

    if ($getLogsExitCode -ne 0) {
        $msg = "Error getting logs for pod $PodName (exit = $getLogsExitCode), checking status"
        Write-Header $msg -LogLevel error
        # TODO if you have multiple containers, this returns multiple chunks of json, but not in an array
        Write-Verbose "kubectl get pod $PodName -o jsonpath='{.status.containerStatuses.*.state}'"
        $state = ,(kubectl get pod $PodName -o jsonpath="{.status.containerStatuses.*.state}" | ConvertFrom-Json -Depth 5)
        foreach ($s in $state) {
            # can have running, waiting, or terminated properties
            if ($s -and (Get-Member -InputObject $s -Name waiting) -and (Get-Member -InputObject $s.waiting -Name reason)) {
                # waiting can have reason, message
                Write-Status "Pod is waiting" -LogLevel error
                Write-Status ($s.waiting | Out-String -Width 500) -LogLevel error
            } elseif ($s -and (Get-Member -InputObject $s -Name terminated) -and (Get-Member -InputObject $s.terminated -Name reason)) {
                # terminated can have containerID, exitCode, finishedAt, reason, message, signal, startedAt
                Write-Status "Pod was terminated" -LogLevel error
                Write-Status ($s.terminated | Out-String -Width 500) -LogLevel error
            } else {
                Write-Warning "Didn't get known state:"
                Write-Warning ($s | Out-String)
            }
        }
        Write-Footer "End status for $prefix $PodName"
    }
}