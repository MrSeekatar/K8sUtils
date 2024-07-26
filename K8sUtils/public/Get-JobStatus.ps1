<#
.SYNOPSIS
Get the status of the pods for a job

.PARAMETER JobName
Name of the K8s job

.PARAMETER ReplicaCount
Number of pods to wait for that match the selector

.PARAMETER PollIntervalSec
Seconds to wait between polls defaults to 5

.PARAMETER TimeoutSecs
Timeout in seconds for waiting on the pods. Defaults to 600

.PARAMETER Namespace
K8s namespace to use, defaults to default

.EXAMPLE
Get-JobStatus -JobName test-job

Get the status of the pods for the job test-job

.OUTPUTS
Array of PodStatus object
#>
function Get-JobStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JobName,
        [ValidateRange(1, 100)]
        [int] $ReplicaCount = 1,
        [ValidateRange(1, 600)]
        [int] $PollIntervalSec = 5,
        [int] $TimeoutSec = 600,
        [string] $Namespace = "default"

    )
    $ErrorActionPreference = 'Stop'
    Set-StrictMode -Version Latest

    Write-Verbose "kubectl get job $JobName --namespace $Namespace -o json"
    $job = kubectl get job $JobName --namespace $Namespace -o json | ConvertFrom-Json

    if ($job) {
        $uid = $job.spec.template.metadata.labels.'batch.kubernetes.io/controller-uid'
        $selector = "batch.kubernetes.io/controller-uid=$uid"
        Write-Verbose "Checking pods for job selector $selector in namespace $Namespace"

        Get-PodStatus -Selector $selector `
            -ReplicaCount $ReplicaCount `
            -PodType Job `
            -Verbose:$VerbosePreference `
            -TimeoutSec $TimeoutSec `
            -PollIntervalSec $PollIntervalSec

    } else {
        Write-Warning "Job $JobName not found in namespace $Namespace"
    }
}
