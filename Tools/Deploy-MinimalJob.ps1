<#
.SYNOPSIS
Helper function to deploy a job via Helm

.PARAMETER DryRun
If set, don't actually do the helm upgrade

.PARAMETER Fail
Have the job fail on start

.PARAMETER InitRunCount
How many times to log a message in the init container, e.g. number of seconds before it exits, defaults to 1

.PARAMETER InitFail
Have the init container fail after InitRunCount loops

.PARAMETER RunCount
How many times to log a message in the job, e.g. number of seconds before it exits, defaults to 1

.PARAMETER ImageTag
Tag to use for the job, defaults to latest

.PARAMETER InitTag
Tag to use for the init container, defaults to latest

.PARAMETER SkipRollbackOnError
If set, don't do a helm rollback on error

.PARAMETER TimeoutSecs
How long to wait for the job to complete, defaults to 600 seconds

.PARAMETER PollIntervalSec
How often to poll for the job to complete, defaults to 3 seconds

.PARAMETER ColorType
Type of color to use for output, defaults to ANSI, can be None or DevOps

.PARAMETER BadSecret
If set, use a bad secret name in the job

.PARAMETER PassThru
If set, return the ReleaseStatus and PodStatus objects instead of writing to the console

.PARAMETER ActiveDeadlineSeconds
How long to wait for the job to complete, defaults to 30 seconds

.EXAMPLE

.OUTPUTS
Array of two items, first is the ReleaseStatus object, second is a PodStatus object

#>
function Deploy-MinimalJob {
    [CmdletBinding()]
    param (
        [switch] $DryRun,
        [int] $InitRunCount = 1,
        [switch] $InitFail,
        [int] $RunCount = 1,
        [switch] $Fail,
        [switch] $SkipInit,
        [string] $InitTag = "latest",
        [string] $ImageTag = "latest",
        [switch] $SkipRollbackOnError,
        [int] $TimeoutSecs = 600,
        [int] $PollIntervalSec = 3,
        [ValidateSet("None", "ANSI", "DevOps")]
        [string] $ColorType = "ANSI",
        [switch] $BadSecret,
        [switch] $PassThru,
        [string] $registry = "docker.io",
        [int] $ActiveDeadlineSeconds = 30
    )
    Set-StrictMode -Version Latest
    $ErrorActionPreference = "Stop"

    Push-Location (Join-Path $PSScriptRoot "../DevOps/helm")

    # to clear out init containers from values.yaml, don't set anything and do this, but requires newer helm
    $helmSet = @()
    # $helmSet += "--set-json"
    # $helmSet += "initContainers=[]"

    $helmJson = ""

    if (!$SkipInit) {
        $initContainer = @{
            image           = "$registry/init-app:$InitTag"
            imagePullPolicy = $($registry -eq "docker.io" ? "Never" : "IfNotPresent")
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
        $helmSet += "secrets.example-secret3=bad-secret"
    }
    $null = kubectl delete job test-job --ignore-not-found # so don't find prev one

    $helmSet += "deployment.enabled=false",
                "registry=$registry",
                "imagePullPolicy=$($registry -eq "docker.io" ? "Never" : "IfNotPresent")",
                "image.pullPolicy=$($registry -eq "docker.io" ? "Never" : "IfNotPresent")",
                "service.enabled=false",
                "preHook.create=false",
                "ingress.enabled=false",
                "jobActiveDeadlineSeconds=$activeDeadlineSeconds",
                "job.create=true",
                "job.fail=$Fail",
                "job.imageTag=$ImageTag",
                "job.runCount=$RunCount"


    Write-Verbose ("HelmSet:`n   "+($helmSet -join "`n   "))
    $releaseName = "test"
    $chartName = "minimal"
    try {
        $ret = Invoke-HelmUpgrade -ValueFile "minimal_values.yaml" `
                           -ChartName $chartName `
                           -ReleaseName $releaseName `
                           -HelmSet ($helmSet -join ',')`
                           -HelmSetJson $helmJson `
                           -DeploymentSelector "" `
                           -PodTimeoutSec 0 `
                           -DryRun:$DryRun `
                           -SkipRollbackOnError:$SkipRollbackOnError `
                           -ColorType $ColorType `
                           -Verbose:$VerbosePreference

        if ($PassThru) {
            $ret
        } else {
            Write-Host "`n"
            $ret | ConvertTo-Json -Depth 10 -EnumsAsStrings
        }
        if (!$DryRun) {
            Write-Host ">>> Helm upgrade done, waiting for job to finish for ${TimeoutSecs}s ..."
            $ret = Get-JobStatus -JobName "test-job" -TimeoutSec $TimeoutSecs -PollIntervalSec $PollIntervalSec -Verbose:$VerbosePreference
            if ($PassThru) {
                $ret
            } else {
                Write-Host "`n"
                $ret | ConvertTo-Json -Depth 10 -EnumsAsStrings
            }
        }
    } catch {
        Write-Error "Error! $_`n$($_.ScriptStackTrace)"
    } finally {
        Pop-Location
    }

}