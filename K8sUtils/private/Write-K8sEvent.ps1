<#
.SYNOPSIS
Private function to write the events the output

.PARAMETER ObjectName
Name of the object to get events for

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

.OUTPUTS
If PassThru is set, return array of strings error messages
#>
function Write-K8sEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Alias("PodName", "RsName")]
        [string]$ObjectName,
        [Parameter(Mandatory)]
        [string]$Prefix,
        [DateTime]$Since,
        [string] $Namespace = "default",
        [ValidateSet("error", "warning", "ok", "normal")]
        [string] $LogLevel = "ok",
        [switch] $PassThru,
        [switch] $FilterStartupWarnings
    )

    $events = Get-K8sEvent -Namespace $Namespace -ObjectName $ObjectName
    if ($null -eq $events) {
        Write-Status "Get-K8sEvent returned null for $ObjectName" -LogLevel warning
        return
    }
    $msg = "Events for $Prefix $ObjectName"
    if ($Since) {
        $msg += " since $($Since.ToString("HH:mm:ss"))"
        $events = $events | Where-Object { $_.lastTimestamp -gt $Since }
    }

    $errors = $events | Where-Object { $_.type -ne "Normal" } | Select-Object -ExpandProperty Message
    if ($errors -and $FilterStartupWarnings) {
        $errors = $errors | Where-Object { $_ -notLike "Startup probe failed:*" }
    }
    $filteredEvents = $events | Select-Object type, reason, message, @{n='creationTimestamp';e={$_.metadata.creationTimestamp}}
    if ($filteredEvents) {
        Write-Header $msg -LogLevel $LogLevel
        $filteredEvents | Out-String -Width 500 | Write-Plain
        Write-Footer "End events for $Prefix $ObjectName"
    } else {
        Write-Status "No $msg" -LogLevel ok
    }

    if ($PassThru) {
        return $errors
    }
}
