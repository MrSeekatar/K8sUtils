<#
.SYNOPSIS
Helper to test using a ThreadJob to get pod logs
#>
[CmdletBinding()]
param (
    [string] $JobName = "test-prehook",
    [string] $Namespace = "default",
    [int] $PollIntervalSec = 1
)

$hasInit = $false
$follow = $true
$logJob = $null
$jobUid = $null
$podUid = $null

while ($true) {
    $job = kubectl get job $JobName --namespace $Namespace -o json | ConvertFrom-Json
    if (!$job) {
        Write-Warning "Could not get job $JobName in namespace $Namespace"
        Start-Sleep -Seconds $PollIntervalSec
        continue
    }
    $jobUid = $job.metadata.uid

    $selector = "batch.kubernetes.io/controller-uid=$jobUid"

    Write-Verbose "kubectl get pod --namespace $Namespace --selector $Selector --sort-by=.metadata.name -o json"
    $pods = kubectl get pod --namespace $Namespace --selector $Selector --sort-by=.metadata.name -o json | ConvertFrom-Json

    if ($pods.items.Count -eq 0) {
        Start-Sleep -Seconds $PollIntervalSec
        Write-Verbose "Waiting ${$PollIntervalSec}s for next attempt to get pods for $Selector in $Namespace..."
    }
    Write-Verbose "Got $($pods.Count) pods from kubectl get pod --namespace $Namespace --selector $Selector"

    $pod = $pods.items[0]
    $podUid = $pod.metadata.uid

    if (!(Get-Member -InputObject $pod.status -Name containerStatuses)) {
        Write-Host "Pod has no containerStatuses yet"
        Start-Sleep -Seconds 1
        continue
    }
    $phase = $pod.status.phase
    Write-Verbose "Pod $($pod.metadata.name) is in $phase phase"

    if ($phase -eq "Pending") {
        Write-Host "Pod is still pending"
        Start-Sleep -Seconds 1
        continue
    } elseif ($phase -in 'Succeeded', 'Failed', 'Unknown') {
        Write-Host "Pod has exit phase: $phase without getting logs"
        break
    }

    $logJob = Start-ThreadJob { param($podName, $timeout, $hasInit, $follow)
        $extraParams = $hasInit ? ("--all-containers", "--prefix") : @()
        if ($follow) {
            $extraParams += "-f"
        }
        kubectl logs $podName --pod-running-timeout=$timeout @extraParams
    } -ArgumentList $pod.metadata.name, 5m, $hasInit, $follow
    break
}

if ($logJob) {
    Write-Verbose "Getting output for jobId is $($logJob.Id)"
    Receive-Job $logJob -Wait -AutoRemoveJob
    Write-Verbose "Finished getting logs for pod $($pod.metadata.name) from jobId $($logJob.Id)"
} else {
    Write-Warning "Did not start log job for pod $($pod.metadata.name)"
}

if ($podUid) {
    "--------------- Pod events"
    $events = Get-K8sEvent -Uid $podUid -Namespace $Namespace
    $events.note
}
if ($jobUid) {
    "--------------- Job events"
    $events = Get-K8sEvent -Uid $jobUid -Namespace $Namespace
    $events.note
}
