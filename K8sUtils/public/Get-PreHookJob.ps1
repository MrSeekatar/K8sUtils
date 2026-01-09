<#
.SYNOPSIS
Worker function that runs inside the thread job to monitor the pre-hook job status

.DESCRIPTION
This function is called from within a thread job to monitor a Helm pre-install hook job.
It imports the K8sUtils module and polls for pod status.

.PARAMETER PreHookJobName
Name of the pre-install hook job to monitor

.PARAMETER Namespace
Kubernetes namespace

.PARAMETER LogFileFolder
Folder to write pod logs to

.PARAMETER StartTime
Time to start looking for events from

.PARAMETER PreHookTimeoutSecs
Timeout in seconds for waiting on the hook job

.PARAMETER PollIntervalSec
How often to poll for status

.PARAMETER Status
ReleaseStatus object to update with hook status
#>

<#
.SYNOPSIS
Starts a thread job to monitor a Helm pre-install hook job

.PARAMETER PreHookJobName
Name of the pre-install hook job to monitor

.PARAMETER Namespace
Kubernetes namespace

.PARAMETER LogFileFolder
Folder to write pod logs to

.PARAMETER StartTime
Time to start looking for events from

.PARAMETER PreHookTimeoutSecs
Timeout in seconds for waiting on the hook job

.PARAMETER Status
ReleaseStatus object to update with hook status

.PARAMETER InformationPreference
Information preference to use in the thread

.PARAMETER VerbosePreference
Verbose preference to use in the thread

.PARAMETER DebugPreference
Debug preference to use in the thread

.OUTPUTS
Returns the ThreadJob object
#>
function Get-PreHookJob {
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
        $Status,
        [System.Management.Automation.ActionPreference] $InformationPreference = 'Continue',
        [System.Management.Automation.ActionPreference] $VerbosePreference = 'SilentlyContinue',
        [System.Management.Automation.ActionPreference] $DebugPreference = 'SilentlyContinue'
    )
    Set-StrictMode -Version Latest
    $ErrorActionPreference = "Stop"

    $statusVar = Get-Variable Status
    $module = Join-Path $PSScriptRoot ../K8sUtils.psd1
    $getPodJob = Start-ThreadJob -ArgumentList $PreHookJobName, $Namespace, $LogFileFolder, $StartTime, $PreHookTimeoutSecs, $InformationPreference, $VerbosePreference, $DebugPreference, $module `
        -ScriptBlock {
        param($PreHookJobName, $Namespace, $LogFileFolder, $startTime, $PreHookTimeoutSecs, $InfoPref, $VerbosePref, $DebugPref, $module)
        $ErrorActionPreference = "Stop"
        Set-StrictMode -Version Latest

        Import-Module $module -ArgumentList $true -Verbose:$false
        Write-Verbose "In thread. Loaded K8sUtil version $((Get-Module K8sUtils).Version). LogFileFolder is '$LogFileFolder'"

function Invoke-PreHookJobWorker {
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
                $errors = Write-K8sEvent -Name "$PreHookJobName's pod" `
                                    -Prefix "PreHookJob" `
                                    -Events $events `
                                    -LogLevel error `
                                    -PassThru
                $Status.PreHookStatus.LastBadEvents = $errors
                Write-Debug "Prehook job '$PreHookJobName' events: $($Status.PreHookStatus.LastBadEvents | ConvertTo-Json -Depth 5 -EnumsAsStrings)"
            } else {
                Write-Verbose "No events found for prehook job '$PreHookJobName' since $StartTime"
            }
        }
    } catch {
        Write-Error "Error getting prehook pod status: $_`n$($_.ScriptStackTrace)"
    }
}

        $inThreadPollIntervalSec = 1
        $status = ($using:statusVar).Value
        $InformationPreference = $InfoPref
        $VerbosePreference = $VerbosePref
        $DebugPreference = $DebugPref

        Invoke-PreHookJobWorker -PreHookJobName $PreHookJobName `
                                -Namespace $Namespace `
                                -LogFileFolder $LogFileFolder `
                                -StartTime $startTime `
                                -PreHookTimeoutSecs $PreHookTimeoutSecs `
                                -PollIntervalSec $inThreadPollIntervalSec `
                                -Status $status
    }
    Write-Verbose "Prehook jobId is $($getPodJob.Id)"
    return $getPodJob
}

