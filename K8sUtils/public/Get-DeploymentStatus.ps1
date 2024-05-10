<#
.SYNOPSIS
Get the status of the pods for a deployment

.PARAMETER Selector
K8s select for finding the deployment

.PARAMETER Namespace
K8s namespace to use, defaults to default

.PARAMETER TimeoutSec
Seconds to wait for the deployment to be ready

.PARAMETER NoColor
If set, don't use color in output

.PARAMETER OutputFile
File to write output to in addition to the console

.EXAMPLE
Get-DeploymentStatus -TimeoutSec $timeoutSec `
                     -Selector "app.kubernetes.io/instance=$ReleaseName,app.kubernetes.io/name=$ChartName"

Get the status of a default Helm deployment labels

.EXAMPLE
Get-DeploymentStatus -Selector "app=platformapi"

Get the status of a helm deployment with a different selector

.OUTPUTS
$True if all pods are running, $False if not
#>
function Get-DeploymentStatus {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string] $Selector,
        [string] $Namespace = "default",
        [int] $TimeoutSec = 30,
        [int] $PollIntervalSec = 1,
        [string] $ColorType,
        [string] $OutputFile
    )

    Set-StrictMode -Version Latest

    Write-Verbose "Get-DeploymentStatus has timeout of $TimeoutSec seconds"
    $createdTempFile = !$OutputFile
    if (!$OutputFile) {
        $OutputFile = Get-TempLogFile
    }

    # get the deployment to get the replica count, loop since it may not be ready yet
    $replicas = $null
    for ( $i = 0; $i -lt 10 -and $null -eq $replicas; $i++) {
        # todo check to see if it exists, or don't use jsonpath since items[0] can fail
        $replicas = kubectl get deploy --namespace $Namespace -l $Selector -o jsonpath='{.items[0].spec.replicas}'
        Start-Sleep -Seconds 1
    }
    if ($LASTEXITCODE -ne 0 || $null -eq $replicas) {
        throw "No data from kubectl get deploy -l $Selector"
    }

    # get the current replicaSet's for hash to get pods in this deployment
    Write-Verbose "kubectl get rs -l $Selector  --namespace $Namespace --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.labels.pod-template-hash}'"
    $hash = kubectl get rs -l "$Selector"  --namespace $Namespace --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.labels.pod-template-hash}'
    if ($LASTEXITCODE -ne 0 || $null -eq $hash) {
        throw "No data from kubectl get rs -l $Selector --namespace $Namespace"
    }
    Write-Status "Looking for $replicas pod$($replicas -eq 1 ? '' : 's') with pod-template-hash=$hash" -Length 0 -LogLevel Normal
    $podSelector = "pod-template-hash=$hash"

    $ret = Get-PodStatus -Selector $podSelector `
                         -OutputFile $OutputFile `
                         -ReplicaCount $replicas `
                         -Namespace $Namespace `
                         -TimeoutSec $TimeoutSec `
                         -PollIntervalSec $PollIntervalSec

    Write-Verbose "ret is ($ret | out-string)"

    if ($createdTempFile) {
        Write-Host "Output was written to $OutputFile"
    }
    return $ret
}