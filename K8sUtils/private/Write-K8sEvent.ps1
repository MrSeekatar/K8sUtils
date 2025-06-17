<#
.SYNOPSIS
Write out Kubernetes events for a given object

.PARAMETER Name
Name of the object to get events for

.PARAMETER Prefix
Prefix for logging, usually the type of the object

.PARAMETER Since
Only get events since this time

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
    param (
        [Parameter(Mandatory)]
        [string] $Name,
        [array] $Events,
        [Parameter(Mandatory)]
        [string] $Prefix,
        [DateTime] $Since,
        [ValidateSet("error", "warning", "ok", "normal")]
        [string] $LogLevel = "ok",
        [switch] $PassThru,
        [switch] $FilterStartupWarnings
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = "Stop"
    $msg = "Events for $Prefix $Name"
    if (!$Events) {
        Write-Status "No $msg" -LogLevel ok
        if ($PassThru) {
            return @()
        }
        return
    }

    if ($Since) {
        $msg += " since $($Since.ToString("HH:mm:ss"))"
        $Events = @($Events | Where-Object { $_.lastTimestamp -gt $Since })
    }
    if ($Events) {
        Write-Verbose ($Events | ConvertTo-Json -Depth 5)
    } else {
        Write-Verbose "No events found for $Prefix $Name since $($Since.ToString("HH:mm:ss"))"
    }
    $errors = $Events | Where-Object { $_.type -ne "Normal" } | Select-Object -ExpandProperty Message
    if ($errors -and $FilterStartupWarnings) {
        $errors = $errors | Where-Object { $_ -notLike "Startup probe failed:*" }
    }
    $filteredEvents = $Events | Select-Object type, reason, message, @{n='creationTimestamp';e={$_.metadata.creationTimestamp}}
    if ($filteredEvents) {
        Write-Header $msg -LogLevel $LogLevel
        $filteredEvents | Out-String -Width 500 | Write-Plain
        Write-Footer "End events for $Prefix $Name"
    } else {
        Write-Status "No $msg" -LogLevel ok
    }

    if ($PassThru) {
        return $errors
    }
}
