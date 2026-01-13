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
function Start-PreHookJobThread {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string] $PreHookJobName,
        [Parameter(Mandatory)]
        [string] $Namespace,
        [string] $LogFileFolder,
        [Parameter(Mandatory)]
        [int] $PreHookTimeoutSecs,
        [Parameter(Mandatory)]
        $Status
    )
    Set-StrictMode -Version Latest
    $ErrorActionPreference = "Stop"

    $StartTime = (Get-CurrentTime ([TimeSpan]::FromSeconds(-5))) # start a few seconds back to avoid very close timing

    $statusVar = Get-Variable Status
    $module = Join-Path $PSScriptRoot ../K8sUtils.psd1
    $getPodJob = Start-ThreadJob -ScriptBlock {
        $ErrorActionPreference = "Stop"
        Set-StrictMode -Version Latest

        Import-Module $using:module -ArgumentList $true -Verbose:$false
        Write-Verbose "In thread. Loaded K8sUtil version $((Get-Module K8sUtils).Version). LogFileFolder is '$using:LogFileFolder'"

        $inThreadPollIntervalSec = 1
        $status = ($using:statusVar).Value
        $InformationPreference = $using:InformationPreference
        $VerbosePreference = $using:VerbosePreference
        $DebugPreference = $using:DebugPreference

        Invoke-PreHookJobWorker -PreHookJobName $using:PreHookJobName `
                                -Namespace $using:Namespace `
                                -LogFileFolder $using:LogFileFolder `
                                -StartTime $using:startTime `
                                -PreHookTimeoutSecs $using:PreHookTimeoutSecs `
                                -PollIntervalSec $inThreadPollIntervalSec `
                                -Status $status
    }
    Write-Verbose "Prehook jobId is $($getPodJob.Id)"
    return $getPodJob
}

