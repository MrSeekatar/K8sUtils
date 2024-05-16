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
function Deploy-Minimal {
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
        [switch] $SkipDeploy
    )
    Set-StrictMode -Version Latest
    $ErrorActionPreference = "Stop"

    Push-Location (Join-Path $PSScriptRoot "../DevOps/helm")

    # to clear out init containers from values.yaml, don't set anything and do this, but requires newer helm
    $helmSet = ""
    # $helmSet += "--set-json"
    # $helmSet += "initContainers=[]"

    $helmJson = ""

    if (!$SkipInit) {
        $initContainer = @{
            image           = "init-app:$InitTag"
            imagePullPolicy = "Never"
            name            = "init-container-app"
            env             = @(
                @{
                    name  = "RUN_COUNT"
                    value = $InitRunCount.ToString()
                },
                @{
                    name  = "FAIL"
                    value = $InitFail.ToString()
                }
            )
            volumeMounts  = @(
                @{
                    name      = "mt"
                    mountPath = "/mt"
                }
            )
        }

        $helmJson = "initContainers=[$($initContainer | ConvertTo-Json -Compress -Depth 5)]"
        # $helmJson = "initContainers=[{`"image`": `"latest`",`"imagePullPolicy`": `"Never`", `"name`": `"init-container-app`",`"env`": [{`"name`": `"RUN_COUNT`",`"value`": `"1`"},{`"name`": `"FAIL`",`"value`": `"False`"}]}]"
    }

    if ($BadSecret) {
        $helmSet += "secrets.example-secret3=bad-secret,"
    }
    if ($StartupProbe) {
        $helmSet += "startupPath=/info,"
    }

    $helmSet += "deployment.enabled=$($SkipDeploy ? "false" : "true")," +
                "env.deployTime=$(Get-Date)," +
                "env.failOnStart=$fail," +
                "env.runCount=$RunCount," +
                "image.tag=$ImageTag," +
                "preHook.create=$(!$SkipPreHook)," +
                "preHook.fail=$HookFail," +
                "preHook.imageTag=$HookTag," +
                "preHook.runCount=$HookRunCount," +
                "readinessPath=$Readiness," +
                "replicaCount=$Replicas"

    Write-Verbose ($helmSet -join " ")
    $releaseName = "test"
    $chartName = "minimal"
    try {
        $ret = Invoke-HelmUpgrade -ValueFile "minimal_values.yaml" `
                           -ChartName $chartName `
                           -ReleaseName $releaseName `
                           -HelmSet $helmSet `
                           -HelmSetJson $helmJson `
                           -DeploymentSelector ($SkipDeploy ? "" : "app.kubernetes.io/instance=$releaseName,app.kubernetes.io/name=$chartName") `
                           -PodTimeoutSec $TimeoutSecs `
                           -PreHookJobName ($SkipPreHook ? $Null : "test-prehook") `
                           -PreHookTimeoutSecs $PreHookTimeoutSecs `
                           -PollIntervalSec $PollIntervalSec `
                           -DryRun:$DryRun `
                           -SkipRollbackOnError:$SkipRollbackOnError `
                           -ColorType $ColorType `
                           -Verbose:$VerbosePreference
        if ($PassThru) {
            $ret
        } else {
            Write-Host "`n"
            $ret | ConvertTo-Json -Depth 5 -EnumsAsStrings
        }
    } catch {
        Write-Error "Error! $_`n$($_.ScriptStackTrace)"
    } finally {
        Pop-Location
    }

}