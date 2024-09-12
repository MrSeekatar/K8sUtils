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

.PARAMETER LogFileFolder
If specified, pod logs will be written to this folder

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
        [string] $LogFileFolder
    )

    Set-StrictMode -Version Latest

    Write-Verbose "Get-DeploymentStatus has timeout of $TimeoutSec seconds and selector $Selector in namespace $Namespace"

    # get the deployment to get the replica count, loop since it may not be ready yet
    $replicas = $null
    $uid = $null
    for ( $i = 0; $i -lt 10 -and $null -eq $replicas; $i++) {
        # todo check to see if it exists, or don't use jsonpath since items[0] can fail
        Write-Verbose "kubectl get deploy --namespace $Namespace -l $Selector -o jsonpath='{.items}'"
        $deployments = kubectl get deploy --namespace $Namespace -l $Selector -o jsonpath='{.items}' | ConvertFrom-Json -Depth 20
        if (!$deployments) {
            Write-Warning "No items from kubectl get deploy -l $Selector. Trying again in 1 second."
        } else {
            $deployment = $deployments | Select-Object -First 1 # handle as hash table
            $replicas = $deployment.spec.replicas
            $uid = $deployment.metadata.uid
            $revision = $deployment.metadata.annotations.'deployment.kubernetes.io/revision'
        }
        Start-Sleep -Seconds 1
    }
    if ($LASTEXITCODE -ne 0 || $null -eq $replicas) {
        throw "No data from kubectl get deploy -l $Selector"
    }

    # get the current replicaSet's for hash to get pods in this deployment
    Write-Verbose "kubectl get rs -l $Selector -o jsonpath={.items[?(@.metadata.annotations.deployment\.kubernetes\.io/revision==`"$revision`")]}"
    $rs = kubectl get rs -l $Selector -o "jsonpath={.items[?(@.metadata.annotations.deployment\.kubernetes\.io/revision==`"$revision`")]}" |
                            ConvertFrom-Json -Depth 20

    if ($LASTEXITCODE -ne 0 -or !$rs) {
        throw "When looking for pod, nothing returned from kubectl get rs -l $Selector --namespace $Namespace. Check selector."
    }
    $hash = $rs.metadata.labels."pod-template-hash"
    Write-Verbose "rs pod-template-hash is $hash"

    Write-Status "Looking for $replicas pod$($replicas -eq 1 ? '' : 's') with pod-template-hash=$hash" -Length 0 -LogLevel Normal
    $podSelector = "pod-template-hash=$hash"

    $ret = Get-PodStatus -Selector $podSelector `
                         -ReplicaCount $replicas `
                         -Namespace $Namespace `
                         -TimeoutSec $TimeoutSec `
                         -PollIntervalSec $PollIntervalSec `
                         -LogFileFolder $LogFileFolder

    Write-Verbose "ret is $($ret | out-string)"

    return $ret
}