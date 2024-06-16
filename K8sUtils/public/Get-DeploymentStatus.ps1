<#
.SYNOPSIS
Get the status of the pods for a deployment

.PARAMETER Selector
K8s select for finding the deployment

.PARAMETER Namespace
K8s namespace to use, defaults to default

.PARAMETER TimeoutSec
Seconds to wait for the deployment to be ready

.PARAMETER PollIntervalSec
How often to poll for pod status. Defaults to 5

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
        [int] $PollIntervalSec = 5,
        [string] $OutputFile
    )

    Set-StrictMode -Version Latest

    Write-Verbose "Get-DeploymentStatus has timeout of $TimeoutSec seconds and selector $Selector in namespace $Namespace"
    $createdTempFile = !$OutputFile
    if (!$OutputFile) {
        $OutputFile = Get-TempLogFile
    }

    # get the deployment to get the replica count, loop since it may not be ready yet
    $replicas = $null
    for ( $i = 0; $i -lt 10 -and $null -eq $replicas; $i++) {
        # todo check to see if it exists, or don't use jsonpath since items[0] can fail
        $items = kubectl get deploy --namespace $Namespace -l $Selector -o jsonpath='{.items}' | ConvertFrom-Json -Depth 20
        if (!$items) {
            Write-Warning "No items from kubectl get deploy -l $Selector"
        } else {
            $replicas = $items[0].spec.replicas
        }
        Start-Sleep -Seconds 1
    }
    if ($LASTEXITCODE -ne 0 || $null -eq $replicas) {
        throw "No data from kubectl get deploy -l $Selector"
    }

    # get the current replicaSet's for hash to get pods in this deployment
    Write-Verbose "kubectl get rs -l $Selector  --namespace $Namespace --sort-by=.metadata.creationTimestamp -o jsonpath='{.items}'"
    # $hash = kubectl get rs -l "$Selector"  --namespace $Namespace --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.labels.pod-template-hash}'
    $items = kubectl get rs -l "$Selector"  --namespace $Namespace --sort-by=.metadata.creationTimestamp -o jsonpath='{.items}' | ConvertFrom-Json -Depth 20
    Write-Verbose "items is $items"
    if ($LASTEXITCODE -ne 0 -or !$items) {
        throw "When looking for preHook, nothing returned from kubectl get rs -l $Selector --namespace $Namespace"
    }
    $hash = $items[-1].metadata.labels."pod-template-hash"

    Write-Status "Looking for $replicas pod$($replicas -eq 1 ? '' : 's') with pod-template-hash=$hash" -Length 0 -LogLevel Normal
    $podSelector = "pod-template-hash=$hash"

    $ret = Get-PodStatus -Selector $podSelector `
                         -OutputFile $OutputFile `
                         -ReplicaCount $replicas `
                         -Namespace $Namespace `
                         -TimeoutSec $TimeoutSec `
                         -PollIntervalSec $PollIntervalSec

    Write-Verbose "ret is $($ret | out-string)"

    if ($createdTempFile) {
        Write-MyHost "Output was written to $OutputFile"
    }
    return $ret
}