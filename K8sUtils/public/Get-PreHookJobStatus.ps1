<#
.SYNOPSIS
 Gets the status of a Kubernetes pre-hook job and populates status information.

.DESCRIPTION
Mainly for internal use. It was split out as a function since now used by a thread, this helps with call stack

.PARAMETER PreHookJobName
The name of the pre-hook job to monitor.

.PARAMETER Namespace
The Kubernetes namespace where the pre-hook job is running.

.PARAMETER LogFileFolder
Optional. The folder path where log files will be written.

.PARAMETER StartTime
The time when monitoring started, used to filter events.

.PARAMETER PreHookTimeoutSecs
The timeout in seconds to wait for the pre-hook job to complete.

.PARAMETER PollIntervalSec
The interval in seconds between status checks.

.PARAMETER Status
A ReleaseStatus object that will be populated with the PreHookStatus property and any error events.

.EXAMPLE
Get-PreHookJobStatus -PreHookJobName "my-hook" -Namespace "default" `
    -StartTime (Get-Date) -PreHookTimeoutSecs 300 -PollIntervalSec 5 -Status $statusObj
#>
function Get-PreHookJobStatus {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory)]
            [string] $PreHookJobName,
            [Parameter(Mandatory)]
            [string] $Namespace,
            [string] $LogFileFolder,
            [Parameter(Mandatory)]
            [datetime] $StartTime,
            [Parameter(Mandatory)]
            [int] $PreHookTimeoutSecs,
            [Parameter(Mandatory)]
            [int] $PollIntervalSec,
            [Parameter(Mandatory)]
            $Status
        )
        Set-StrictMode -Version Latest
        $ErrorActionPreference = "Stop"

        try {

            $hookStatus = Get-PodStatus -Selector "job-name=$PreHookJobName" `
                                        -Namespace $Namespace `
                                        -TimeoutSec $PreHookTimeoutSecs `
                                        -PollIntervalSec $PollIntervalSec `
                                        -PodType PreInstallJob `
                                        -LogFileFolder $LogFileFolder
            Write-Debug "Prehook status is $($hookStatus | ConvertTo-Json -Depth 5 -EnumsAsStrings)"
            if ($hookStatus -is "array" ) {
                Write-Warning "Multiple hook statuses returned:`n$($hookStatus  | ConvertTo-Json -Depth 5 -EnumsAsStrings)" # so we can see the status
            }
            $Status.PreHookStatus = $hookStatus | Select-Object -Last 1 # get the last status, in case it was a job
            if ($Status.PreHookStatus.PodName -eq '<no pods found>') {
                $events = Get-JobPodEvent -JobName $PreHookJobName -Since $StartTime
                if ($events) {
                    $errors = Write-K8sEvent -Name "$PreHookJobName's pod since $StartTime" `
                                        -Prefix "PreHookJob" `
                                        -Events $events `
                                        -LogLevel error `
                                        -PassThru
                    $Status.PreHookStatus.LastBadEvents = $errors
                    Write-Debug "Prehook job '$PreHookJobName' events: $($Status.PreHookStatus.LastBadEvents | ConvertTo-Json -Depth 5 -EnumsAsStrings)"
                } else {
                    Write-VerboseStatus "No events found for prehook job '$PreHookJobName' since $StartTime"
                }
            }
        } catch {
            Write-Error "Error getting prehook pod status: $_`n$($_.ScriptStackTrace)"
        }
    }

