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
    param (
        [string] $JobName,
        [string] $Namespace = "default"
    )

    (kubectl get pod --namespace $Namespace --selector "job-name=$JobName" -o json | ConvertFrom-Json).items
}

