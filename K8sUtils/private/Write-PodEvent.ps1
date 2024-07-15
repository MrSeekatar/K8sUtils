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
    if (!$events) {
        Write-Error "Failed to get events for pod $PodName"
        return
    }
    $msg = "Events for $Prefix $PodName"
    if ($Since) {
        $msg += " since $($Since.ToString("HH:mm:ss"))"
        $events = $events | Where-Object { $_.lastTimestamp -gt $Since }
    }

    $errors = $events | Where-Object { $_.type -ne "Normal" } | Select-Object -ExpandProperty Message

    Write-Header $msg -LogLevel $LogLevel
    if ($errors -and $FilterStartupWarnings) {
        $errors = $errors | Where-Object { $_ -notLike "Startup probe failed:*" }
    }
    $events | Select-Object type, reason, message, @{n='creationTimestamp';e={$_.metadata.creationTimestamp}} | Out-String | Write-Plain
    Write-Footer "End events for $Prefix $PodName"
    if ($PassThru) {
        return $errors
    }
}