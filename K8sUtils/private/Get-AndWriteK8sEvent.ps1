<#
.SYNOPSIS
Private function to get events and write them out

.PARAMETER ObjectName
Name of the object to get events for

.PARAMETER Uid
Uid of the object to get events for

.PARAMETER Prefix
Prefix for logging, usually the type of the object

.PARAMETER Since
Only get events since this time

.PARAMETER Namespace
Namespace to get the events from

.PARAMETER LogLevel
Log level to use for the header

.PARAMETER PassThru
Return any errors messages found in events

.PARAMETER FilterStartupWarnings
Filter out startup warnings if pod is running ok

.PARAMETER NoNormal
If set, do not include normal events in the output

.OUTPUTS
If PassThru is set, return array of strings error messages
#>
function Get-AndWriteK8sEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ParameterSetName = "ObjectName")]
        [Alias("PodName", "RsName")]
        [string] $ObjectName,
        [Parameter(Mandatory, ParameterSetName = "Uid")]
        [string] $Uid,
        [Parameter(Mandatory)]
        [string] $Prefix,
        [DateTime] $Since,
        [string] $Namespace = "default",
        [ValidateSet("error", "warning", "ok", "normal")]
        [string] $LogLevel = "ok",
        [switch] $PassThru,
        [switch] $FilterStartupWarnings,
        [switch] $NoNormal
    )

    $params = @{
        Namespace = $Namespace
    }
    if ($Uid) {
        $params["Uid"] = $Uid
        $name = $Uid
    } else {
        $params["ObjectName"] = $ObjectName
        $name = $ObjectName
    }
    if ($NoNormal) {
        $params["NoNormal"] = $true
    }
    $events = Get-K8sEvent @params
    if ($null -eq $events) {
        Write-Status "Get-K8sEvent returned null for $ObjectName" -LogLevel warning
        return
    }
    $params = @{}
    if ($Since) {
        $params["Since"] = $Since
    }
    Write-K8sEvent $events -Prefix $Prefix -LogLevel $LogLevel -PassThru:$PassThru -FilterStartupWarnings:$FilterStartupWarnings @params -Name $name
}

