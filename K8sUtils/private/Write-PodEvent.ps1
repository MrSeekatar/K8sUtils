<#
.SYNOPSIS
Private function to write the events for a pod to the output

.PARAMETER PodName
Name of the pod to get events for

.PARAMETER Prefix
Prefix for logging

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
#>
function Write-PodEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PodName,
        [Parameter(Mandatory)]
        [string]$Prefix,
        [DateTime]$Since,
        [string] $Namespace = "default",
        [ValidateSet("error", "warning", "ok", "normal")]
        [string] $LogLevel = "ok",
        [switch] $PassThru,
        [switch] $FilterStartupWarnings
    )

    $events = Get-PodEvent -Namespace $Namespace -PodName $PodName
    if ($null -eq $events) {
        Write-Status "Get-PodEvent returned null for pod $PodName" -LogLevel warning
        return
    }
    $msg = "Events for $Prefix $PodName"
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
        Write-Footer "End events for $Prefix $PodName"
    } else {
        Write-Status "No $msg" -LogLevel ok
    }

    if ($PassThru) {
        return $errors
    }
}