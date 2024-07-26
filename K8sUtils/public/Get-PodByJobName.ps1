<#
.SYNOPSIS
Get Pod object by job name

.PARAMETER JobName
Job name to get pods for

.PARAMETER Namespace
K8s namespace to use, defaults to default

.EXAMPLE
An example

.OUTPUTS
One or more pods for the job
#>
function Get-PodByJobName {
    [CmdletBinding()]
    param (
        [string] $JobName,
        [string] $Namespace = "default"
    )

    Write-Verbose "kubectl get job $JobName --namespace $Namespace -o json"
    $job = kubectl get job $JobName --namespace $Namespace -o json | ConvertFrom-Json
    if ($job) {
        Write-Verbose "kubectl get pod --namespace $Namespace --selector 'batch.kubernetes.io/controller-uid=$($job.metadata.labels.'batch.kubernetes.io/controller-uid')' -o json"
        (kubectl get pod --namespace $Namespace --selector "batch.kubernetes.io/controller-uid=$($job.metadata.labels.'batch.kubernetes.io/controller-uid')" -o json | ConvertFrom-Json).items
    } else {
        Write-Warning "Job $JobName not found in namespace $Namespace"
    }
    return @()
}

