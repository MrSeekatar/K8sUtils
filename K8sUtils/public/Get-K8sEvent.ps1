<#
.SYNOPSIS
Get events for a pod

.PARAMETER PodName
Name of the pod to get events for

.PARAMETER NoNormal
If set, don't return normal events, only warnings

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
function Get-PodEvent {
    param (
        [CmdletBinding()]
        [Parameter(Mandatory = $true)]
        [string] $PodName,
        [switch] $NoNormal,
        [string] $Namespace = "default"
    )
    Write-Verbose "kubectl get events --namespace $Namespace --field-selector `"involvedObject.name=$PodName`" -o json"
    $json = kubectl get events --namespace $Namespace --field-selector "involvedObject.name=$PodName" -o json

    Write-Verbose "kubectl exit code: $LASTEXITCODE"
    if ($LASTEXITCODE -ne 0) {
        Write-Status "kubectl get events --namespace $Namespace --field-selector `"involvedObject.name=$PodName`" -o json" -LogLevel warning
        Write-Status "  had exit code of $LASTEXITCODE" -LogLevel warning
        Write-Status "  JSON is $json" -LogLevel warning
        return $null
    }
    $events = $json | ConvertFrom-Json
    if ($null -eq $events) { # valid if no events, such as it didn't need to create a new pod
        Write-Verbose "Null events after conversion"
        Write-Output @() -NoEnumerate # Prevent @() from turning into $null
        return
    }
    if ($events.items) {
        Write-Verbose "Events count: $($events.items.count)"
    }
    if ($NoNormal) {
        $ret = $events.items | Where-Object { $_.type -ne "Normal" }
    } else {
        $ret = $events.items
    }
    if ($null -eq $ret) {
        Write-Verbose "Null items, returning empty array"
        $ret = @()
    }
    Write-Output $ret -NoEnumerate
}
