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
        [string] $OutputFile = $script:OutputFile
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

    Write-Header $msg -LogLevel $LogLevel -OutputFile $OutputFile
    kubectl logs --namespace $Namespace $PodName $extraLogParams 2>&1 |
        Where-Object { $_ -NotMatch 'Error.*: (PodInitializing|ContainerCreating)' } | Tee-Object $OutputFile -Append | Write-Host
    $getLogsExitCode = $LASTEXITCODE
    Write-Footer "End logs for $prefix $PodName" -LogLevel $LogLevel -OutputFile $OutputFile

    if ($getLogsExitCode -ne 0) {
        $msg = "Failed to get logs for pod $PodName ($LASTEXITCODE), checking status"
        Write-Header $msg -LogLevel error -OutputFile $OutputFile
        $state = ,(kubectl get pod $PodName -o jsonpath="{.status.containerStatuses.*.state}" | ConvertFrom-Json -Depth 5)
        foreach ($s in $state) {
            if ($s -and (Get-Member -InputObject $s -Name waiting) -and (Get-Member -InputObject $s.waiting -Name reason)) {
                Write-Status ($s.waiting | Out-String -Width 500) -LogLevel error
            } else {
                Write-Warning "Didn't get state"
                Write-Warning ($s | Out-String)
            }
        }
        Write-Footer "End status for $prefix $PodName" -LogLevel error -OutputFile $OutputFile
    }
}