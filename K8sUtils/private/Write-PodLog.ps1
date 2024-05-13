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
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Failed to get logs for pod $PodName ($LASTEXITCODE), checking status"
        $state = ,(kubectl get pod $PodName -o jsonpath="{.status.containerStatuses.*.state}" | ConvertFrom-Json -Depth 5)
        foreach ($s in $state) {
            if ($s -and (Get-Member -InputObject $s -Name waiting) -and (Get-Member -InputObject $s.waiting -Name reason)) {
                Write-Status ($s.waiting | Out-String -Width 500) -LogLevel error
            } else {
                Write-Warning "Didn't get state"
                Write-Warning ($s | Out-String)
            }
        }

    }
    Write-Footer "End logs for $prefix $PodName" -OutputFile $OutputFile
}