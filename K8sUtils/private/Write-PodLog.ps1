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
        Write-Warning "Failed to get logs for pod $PodName ($LASTEXITCODE)"
    }
    Write-Footer "End logs for $prefix $PodName" -OutputFile $OutputFile
}