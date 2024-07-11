<#
.SYNOPSIS
Get events for a pod

.PARAMETER PodName
Name of the pod to get events for

.PARAMETER NoNormal
If set, don't return normal events

.PARAMETER Namespace
K8s namespace to use, defaults to default

.EXAMPLE
Get-PodEvent -PodName mypod

Get all events for pod mypod

.EXAMPLE
Get-PodEvent -PodName mypod -NoNormal -Namespace test

Get all non-normal events for pod mypod in namespace test

.OUTPUTS
One or more event objects for the pod, $null if error
#>
function Get-PodEvent(
    [Parameter(Mandatory = $true)]
    [string] $PodName,
    [switch] $NoNormal,
    [string] $Namespace = "default"
    )
{
    $events = kubectl get events --namespace $Namespace --field-selector "involvedObject.name=$PodName" -o json | ConvertFrom-Json

    if ($LASTEXITCODE -ne 0 -or $null -eq $events) {
        return $null
    }
    if ($NoNormal) {
        $events.items | Where-Object { $_.type -ne "Normal" }
    } else {
        $events.items
    }
}
