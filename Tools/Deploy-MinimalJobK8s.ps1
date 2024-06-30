<#
.SYNOPSIS
Helper function to deploy the minimal chart

.PARAMETER DryRun
If set, don't actually do the helm upgrade

.PARAMETER Fail
Have the main container fail on start

.PARAMETER InitRunCount
How many times to log a message in the init container, e.g. number of seconds before it exits, defaults to 1

.PARAMETER InitFail
Have the init container fail after InitRunCount loops

.PARAMETER HookRunCount
How many times to log a message in the helm preHook job, e.g. number of seconds before it exits, defaults to 1

.PARAMETER SkipPreHook
Do not run the preHook job

.PARAMETER HookFail
Have the preHook job fail after HookRunCount loops

.PARAMETER ImageTag
Tag to use for the main container, defaults to latest

.PARAMETER InitTag
Tag to use for the init container, defaults to latest

.PARAMETER HookTag
Tag to use for the preHook job, defaults to latest

.PARAMETER StartupProbe
Add a startup probe to the main container

.PARAMETER Readiness
Readiness url to use, defaults to /info

.PARAMETER SkipRollbackOnError
If set, don't do a helm rollback on error

.EXAMPLE

.NOTES
General notes
#>
function Deploy-MinimalJobK8s {
    [CmdletBinding()]
    param (
        [switch] $DryRun,
        [switch] $Fail,
        [int] $RunCount = 0,
        [int] $InitRunCount = 1,
        [switch] $InitFail,
        [int] $HookRunCount = 1,
        [switch] $SkipPreHook,
        [switch] $HookFail,
        [switch] $SkipInit,
        [string] $ImageTag = "latest",
        [string] $InitTag = "latest",
        [string] $HookTag = "latest",
        [string] $Readiness = "/info",
        [switch] $SkipRollbackOnError,
        [int] $TimeoutSecs = 600,
        [int] $PreHookTimeoutSecs = 15,
        [int] $PollIntervalSec = 3,
        [int] $Replicas = 1,
        [ValidateSet("None", "ANSI", "DevOps")]
        [string] $ColorType = "ANSI",
        [switch] $BadSecret,
        [switch] $PassThru,
        [switch] $StartupProbe,
        [switch] $SkipDeploy,
        [switch] $AlwaysCheckPreHook

    )
    Set-StrictMode -Version Latest
    $ErrorActionPreference = "Stop"

    Push-Location (Join-Path $PSScriptRoot "../DevOps/Kubernetes")

    try {
        kubectl apply -f .\test-job.yaml
        Get-PodStatus -Selector "batch.kubernetes.io/job-name=test-job" -ReplicaCount 1 -PodType PreInstallJob -Verbose:$VerbosePreference
        kubectl delete job test-job --ignore-not-found
    } catch {
        Write-Error "Error! $_`n$($_.ScriptStackTrace)"
    } finally {
        Pop-Location
    }

}