<#
.SYNOPSIS
Get events for an object

.PARAMETER ObjectName
Name of the object to get events for

.PARAMETER Uid
Uid of the object to get events for

.PARAMETER NoNormal
If set, don't return normal events, only warnings

.PARAMETER Namespace
K8s namespace to use, defaults to default

.PARAMETER Kind
Kind of the object to get events for, such as Pod, ReplicaSet, Job, etc. Case sensitive

.EXAMPLE
Get-K8sEvent -ObjectName  test-minimal-7894b5dbf9-xkvgc

Get all events for a pod

.EXAMPLE
Get-K8sEvent -ObjectName test-minimal-7894b5dbf9-xkvgc -NoNormal -Namespace test

Get all non-normal events for a pod in namespace test

.EXAMPLE
Get-K8sEvent -ObjectName test-minimal-bf9c4b7f9 -NoNormal -Namespace test

Get all non-normal events for a replicaset in namespace test

.OUTPUTS
One or more event objects for the pod, $null if error
#>
function Get-K8sEvent {
    [CmdletBinding()]
    param (
        [CmdletBinding()]
        [Parameter(Mandatory, ParameterSetName = "ObjectName")]
        [Alias("PodName", "RsName","JobName")]
        [string] $ObjectName,
        [Parameter(Mandatory, ParameterSetName = "Uid")]
        [string] $Uid,
        [switch] $NoNormal,
        [string] $Namespace = "default",
        [string] $Kind
    )
    $selector = [bool]$ObjectName ? "involvedObject.name=$ObjectName" : "involvedObject.uid=$Uid"
    if ($NoNormal) {
        $selector += ",type!=Normal"
    }
    if ($Kind) {
        $selector += ",involvedObject.kind=$Kind"
    }
    Write-Verbose "kubectl get events --namespace $Namespace --field-selector `"$selector`" -o json"
    $json = kubectl get events --namespace $Namespace --field-selector $selector -o json

    Write-Verbose "kubectl exit code: $LASTEXITCODE"
    if ($LASTEXITCODE -ne 0) {
        Write-Status "kubectl get events --namespace $Namespace --field-selector `"$selector`" -o json" -LogLevel warning
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
        $events.items | ForEach-Object {
            Write-Verbose "  $($_.message) $($_.eventTime ? $_.eventTime : $_.lastTimestamp)"
        }
    }
    $ret = $events.items
    if ($null -eq $ret) {
        Write-Verbose "Null items, returning empty array"
        $ret = @()
    }
    Write-Output $ret -NoEnumerate
}

Set-Alias -Name Get-PodEvent -Value Get-K8sEvent -Description "Get events for a pod"
Set-Alias -Name Get-RsEvent -Value Get-K8sEvent -Description "Get events for a replica set"
Set-Alias -Name Get-JobEvent -Value Get-K8sEvent -Description "Get events for a job"
Set-Alias -Name Get-EventByUid -Value Get-K8sEvent -Description "Get events by UID"
Set-Alias -Name Get-ReplicaSetEvent -Value Get-K8sEvent -Description "Get events for a replica set"