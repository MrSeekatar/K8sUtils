<#
.SYNOPSIS
Wait for a Kubernetes pods to appear after a specified time

.PARAMETER Selector
Kubernetes label selector to identify the pods

.PARAMETER PreHookJobName
Build the selector from this pre-hook job name

.PARAMETER Namespace
Kubernetes namespace where the job is running, default is "default"

.PARAMETER AfterTime
DateTime object specifying the minimum creation time for pods (default: current server time)

.PARAMETER PreHookTimeoutSecs
Maximum time in seconds to wait for pods to appear (default: 10)

.PARAMETER PollIntervalSec
Time in seconds between polling attempts (default: 1)

.OUTPUTS
Returns $true if pods are found, $false if timeout is reached.
#>
function Wait-PreHookJob {
    param (
        [Parameter(Mandatory,ParameterSetName="Selector")]
        [string] $Selector,
        [Parameter(Mandatory,ParameterSetName="JobName")]
        [string] $PreHookJobName,
        [string] $Namespace = "default",
        [DateTime] $AfterTime = (Get-K8sServerTime),
        [int] $PreHookTimeoutSecs = 10,
        [int] $PollIntervalSec = 1
    )
    Set-StrictMode -Version Latest
    $ErrorActionPreference = "Stop"

    if ($PreHookJobName) {
        $Selector = "job-name=$PreHookJobName"
    }

    $start = Get-Date
    while ($((Get-Date) - $start).TotalSeconds -lt $PreHookTimeoutSecs) {
        $pods = Get-PodAfterTime -Selector $Selector -AfterTime $AfterTime -Namespace $Namespace
        if ($pods) {
            Write-Verbose "Found one or more pods for selector '$Selector' after $AfterTime"
            return $true
        }
        Start-Sleep -Seconds $PollIntervalSec
    }
    Write-Warning "Didn't find any pods selector '$Selector' after ${PreHookTimeoutSecs}s"
    return $false
}
