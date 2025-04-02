<#
.SYNOPSIS
Get the selector for pods for a job

.PARAMETER JobName
Name of the job to get the selector for

.PARAMETER Namespace
Namespace to use, defaults to default

.EXAMPLE
Get-PodStatus -PodType Pod -Selector (Get-JobPodSelector -JobName file-watcher-job)

Get the pod status for the pod in the job file-watcher-job

#>
function Get-JobPodSelector {
    param (
        [Parameter(Mandatory)]
        [string] $JobName,
        [string] $Namespace = "default"
    )
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $job = kubectl get job $JobName --namespace $Namespace -o json | ConvertFrom-Json

    if ($job) {
        $uid = $job.spec.template.metadata.labels.'batch.kubernetes.io/controller-uid'
        return "batch.kubernetes.io/controller-uid=$uid"
    }
    return $null
}
