<#
.SYNOPSIS
Invoke helm upgrade using helper scripts to catch errors, and rollback

.PARAMETER ValueFile
Name of the helm values file to use

.PARAMETER ChartName
Name of the helm chart to use in the upgrade

.PARAMETER ReleaseName
Name of the helm release

.PARAMETER DeploymentSelector
K8s select used to find your deployment, defaults to app.kubernetes.io/instance=$ReleaseName,app.kubernetes.io/name=$ChartName

.PARAMETER Chart
Path to the chart folder or tgz, or url, defaults to .

.PARAMETER ChartVersion
Version of the helm chart to use

.PARAMETER Namespace
K8s namespace to use, defaults to default

.PARAMETER PreHookJobName
If set, watches for a helm pre-install job

.PARAMETER HelmSet
Any additional values to set with --set for helm

.PARAMETER HelmSetJson
Any additional values to set with --set-json for helm

.PARAMETER PodTimeoutSecs
Timeout in seconds for waiting on the pods. Defaults to 600

.PARAMETER PreHookTimeoutSecs
Timeout in seconds for waiting on the helm pre-install job to complete, if PreHookJobName is set. Defaults to 60

.PARAMETER PollIntervalSec
How often to poll for pod status. Defaults to 5

.PARAMETER SkipRollbackOnError
If set, don't do a helm rollback on error

.PARAMETER DryRun
If set, don't actually do the helm upgrade

.PARAMETER ColorType
How to colorize the output. Defaults to DevOps if TF_BUILD env var, otherwise ANSI colors

.EXAMPLE
    $parms = "preHook.fail=$HookFail," +
              "preHook.imageTag=$HookTag," +
              "preHook.create=$(!$SkipPreHook)"

    Invoke-HelmUpgrade -ValueFile "minimal_values.yaml" `
                        -ChartName 'minimal' `
                        -ReleaseName "test" `
                        -HelmSet $parms `
                        -PreHookJobName "test-prehook"

Do a Helm upgrade with a prehook job, and a few overrides

.EXAMPLE
# put secrets in the new-values.yml file
Convert-Value "~/code/BackendTemplate/DevOps/helm/values.yaml" `
        -Variables @{
            imageTag = 108021
            fullEnvironmentName = "test"
            'cert-password' = $env:cert_password
            environmentName = "test"
            availabilityZoneLower = "sc"
        } | Out-File ./new-values.yml

Invoke-HelmUpgrade -ValueFile "./values.yml" `
                    -ChartName 'my-chart' `
                    -Chart '~/code/DevOps/helm-charts/internal-charts/my-chart-template' `
                    -ReleaseName "backendtemplate-api" `
                    -PreHookJobName "backendtemplate-api" `
                    -PreHookTimeoutSecs 120 `
                    -DeploymentSelector app=backendtemplate-api `
                    -SkipRollbackOnError -Verbose

Do a Helm upgrade of a backend template to test with a pre-install hook that has a job named backendtemplate-api

.EXAMPLE
# put secrets in the new-values.yml file
Convert-Value "~/code/BackendTemplate/DevOps/helm/values.yaml" `
        -Variables @{
            imageTag = 114090
            fullEnvironmentName = "dev"
            'cert-password' = $env:cert_password
            environmentName = "dev"
            availabilityZoneLower = "sc"
        } | Out-File ./new-values.yml

Invoke-HelmUpgrade -ValueFile "./new-values.yml" `
                     -ChartName 'my-chart' `
                     -Chart '~/code/DevOps/helm-charts/internal-charts/my-chart-template' `
                     -ReleaseName "hrabuilder-api" `
                     -DeploymentSelector app=hrabuilder-api `
                     -Verbose

Do a Helm upgrade of a hra builder to dev


#>
function Invoke-HelmUpgrade {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingCmdletAliases','', Justification = 'Locally helm is an alias')]
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string] $ValueFile,
        [Parameter(Mandatory)]
        [string] $ChartName,
        [Parameter(Mandatory)]
        [string] $ReleaseName,
        [string] $DeploymentSelector = "app.kubernetes.io/instance=$ReleaseName,app.kubernetes.io/name=$ChartName",
        [string] $Chart = '.',
        [string] $ChartVersion,
        [string] $Namespace = "default",
        [string] $PreHookJobName,
        [string] $HelmSet,
        [string] $HelmSetJson,
        [int] $PodTimeoutSecs = 600,
        [int] $PreHookTimeoutSecs = 60,
        [int] $PollIntervalSec = 5,
        [switch] $SkipRollbackOnError,
        [switch] $DryRun,
        [ValidateSet("None","ANSI","DevOps")]
        [string] $ColorType = $script:ColorType
    )
    Set-StrictMode -Version Latest
    $ErrorActionPreference = "Stop"

    $minPreHookTimeoutSecs = 120
    $minPodTimeoutSecs = 180

    function rollbackAndWarn {
        [CmdletBinding()]
        param ($SkipRollbackOnError, $releaseName, $msg, $prevVersion)

        try {
            $currentReleaseVersion = helm status --namespace $Namespace $ReleaseName -o json | ConvertFrom-Json -Depth 10
            if (!$currentReleaseVersion -or !(Get-Member -InputObject $currentReleaseVersion -Name version)) {
                Write-Status "Unexpected response from helm status, not rolling back" -LogLevel warning -Char '-'
                Write-Warning (""+$currentReleaseVersion | ConvertTo-Json -Depth 5 -EnumsAsStrings)
                return [RollbackStatus]::HelmStatusFailed
            }
            Write-Verbose "Current version of $ReleaseName is $($currentReleaseVersion.version)"
            if (!$currentReleaseVersion -or $currentReleaseVersion.version -eq $prevVersion) {
                Write-Status "No change in release $ReleaseName, not rolling back" -LogLevel warning -Char '-'
                # throw "$msg, no change"
                Write-Warning "$msg, no change"
                return [RollbackStatus]::NoChange
            }

            if (!$SkipRollbackOnError) {
                Write-Header "Rolling back release $ReleaseName due to errors" -LogLevel Error
                $errFile = Get-TempLogFile
                helm rollback $ReleaseName 2>&1 | Tee-Object $errFile | Write-MyHost
                Get-Content $errFile -Raw | Out-File $tempFile -Append
                $exit = $LASTEXITCODE
                $content = Get-Content $errFile -Raw
                $content | Out-File $OutputFile -Append
                if ($exit -ne 0 -and ($content -like '*Error: release has no 0 version*' -or $content -like '*Error: release: not found*')) {
                    Write-Verbose "Last exit code on rollback was $exit. Contents of ${errFile}:`n$content"
                    Write-Status "helm rollback failed, trying uninstall" -LogLevel Error -Char '-'
                    helm uninstall $ReleaseName | Out-File $OutputFile -Append
                }
                Write-Footer "End rolling back release $ReleaseName due to errors" -LogLevel Error
                Remove-Item $errFile -ErrorAction SilentlyContinue
                # throw "$msg, rolled back"
                Write-Warning "$msg, rolled back"
                return [RollbackStatus]::RolledBack
            } else {
                # throw "$msg, but not rolling back since -SkipRollbackOnError was specified"
                Write-Warning "$msg, but not rolling back since -SkipRollbackOnError was specified"
                return [RollbackStatus]::Skipped
            }
            return [RollbackStatus]::DeployedOk
        } catch {
            Write-Warning "Caught error rolling back in catch"
            Write-Error "$_`n$($_.ScriptStackTrace)"
            return [RollbackStatus]::HelmStatusFailed
        }
    }

    if (!(Get-Command helm -ErrorAction SilentlyContinue) -or !(Get-Command kubectl -ErrorAction SilentlyContinue)) {
        throw "helm and kubectl must be installed and in the path"
    }

    $prev = $script:ColorType
    if ($ColorType) {
        $script:ColorType = $ColorType
    }

    $parms = @()
    if ($DryRun) {
        $parms += "--dry-run"
    }
    if ($HelmSet) {
        $parms += "--set"
        $parms += $HelmSet
    }
    if ($HelmSetJson) {
        $parms += "--set-json"
        $parms += $HelmSetJson
    }
    if ($ChartVersion) {
        $parms += "--version"
        $parms += $ChartVersion
    }
    Write-Verbose "Parameters:"
    Write-Verbose "    ValueFile: $ValueFile"
    Write-Verbose "    ChartName: $ChartName"
    Write-Verbose "    ReleaseName: $ReleaseName"
    Write-Verbose "    DeploymentSelector: $DeploymentSelector"
    Write-Verbose "    Chart: $Chart"
    Write-Verbose "    ChartVersion: $ChartVersion"
    Write-Verbose "    Namespace: $Namespace"
    Write-Verbose "    PreHookJobName: $PreHookJobName"
    Write-Verbose "    PodTimeoutSecs: $PodTimeoutSecs"
    Write-Verbose "    PreHookTimeoutSecs: $PreHookTimeoutSecs"
    Write-Verbose "    PollIntervalSec: $PollIntervalSec"
    Write-Verbose "    SkipRollbackOnError: $SkipRollbackOnError"
    Write-Verbose "    DryRun: $DryRun"
    Write-Verbose "    ColorType: $ColorType"
    Write-Verbose "Helm extra params $($parms -join " ")"


    $tempFile = Get-TempLogFile

    if (!$env:invokeHelmAllowLowTimeouts){
        if ($PreHookTimeoutSecs -lt $minPreHookTimeoutSecs) {
            Write-Warning "PreHookTimeoutSecs ($PreHookTimeoutSecs) is less than $minPreHookTimeoutSecs seconds, setting to $minPreHookTimeoutSecs."
            $PreHookTimeoutSecs = $minPreHookTimeoutSecs
        }
        if ($PodTimeoutSecs -lt $minPodTimeoutSecs) {
            Write-Warning "PodTimeoutSecs ($PodTimeoutSecs) is less than $minPodTimeoutSecs seconds, setting to $minPodTimeoutSecs."
            $PodTimeoutSecs = $minPodTimeoutSecs
        }
    } elseif ($PreHookTimeoutSecs -lt $minPreHookTimeoutSecs -or $PodTimeoutSecs -lt 180) {
        Write-Warning "Override allowing PreHookTimeoutSecs ($PreHookTimeoutSecs) is less than $minPreHookTimeoutSecs seconds, or PodTimeoutSecs ($PodTimeoutSecs) is less than 180 seconds."
    }

    $status = [ReleaseStatus]::new($ReleaseName)
    try {
        $hookMsg = $PreHookJobName ? " waiting ${PreHookTimeoutSecs}s prehook job '$PreHookJobName'" : ""

        $prevReleaseVersion = helm status --namespace $Namespace $ReleaseName -o json | ConvertFrom-Json
        if ($prevReleaseVersion -and (Get-Member -InputObject $prevReleaseVersion -Name version -MemberType Property)) {
            $prevVersion = $prevReleaseVersion.version
            Write-Verbose "Previous version of $ReleaseName was $prevVersion"
        } else {
            $prevVersion = 0
        }
        "helm upgrade $ReleaseName $Chart --install -f $ValueFile --reset-values --timeout ${PreHookTimeoutSecs}s --namespace $Namespace $($parms -join " ")" | Tee-Object $tempFile -Append | Write-MyHost

        if ($DryRun) {
            Write-Status "Doing a helm dry run. Helm output and manifests follow."
        } else {
            Write-Header "Helm upgrade$hookMsg"
        }
        # Helm's default timeout is 5 minutes. This doesn't return until preHook is done
        helm upgrade --install $ReleaseName $Chart -f $ValueFile --reset-values --timeout "${PreHookTimeoutSecs}s" --namespace $Namespace @parms 2>&1 | Tee-Object $tempFile -Append | Write-MyHost
        $upgradeExit = $LASTEXITCODE

        if ($DryRun) {
            return
        } else {
            Write-Footer "End Helm upgrade (exit code $upgradeExit)"
        }

        if ($PreHookJobName) {
            $hookStatus = Get-PodStatus -Selector "job-name=$PreHookJobName" `
                                                        -Namespace $Namespace `
                                                        -OutputFile $tempFile `
                                                        -TimeoutSec 1 `
                                                        -PollIntervalSec $PollIntervalSec `
                                                        -IsJob
            Write-Verbose "Prehook status is $($hookStatus | ConvertTo-Json -Depth 5 -EnumsAsStrings)"
            $status.PreHookStatus = $hookStatus

            if ($upgradeExit -ne 0 -or !$hookStatus) {
                $status.Running = $false
                Write-Verbose "Helm upgrade failed, setting prehook status to timeout"
                if ($status.PreHookStatus -and
                    $status.PreHookStatus.Status -eq [Status]::Running ) { # assume timeout if prehook is running
                    $status.PreHookStatus.Status = [Status]::Timeout
                }
                $status.RollbackStatus = rollbackAndWarn -SkipRollbackOnError $SkipRollbackOnError `
                                                         -releaseName $ReleaseName `
                                                         -msg "Helm upgrade got last exit code $upgradeExit" `
                                                         -prevVersion $prevVersion
                Write-Output $status
                return
            }
        }

        if ($DeploymentSelector) {
            $podStatuses = Get-DeploymentStatus -TimeoutSec $PodTimeoutSecs `
                                    -Namespace $Namespace `
                                    -Selector $DeploymentSelector `
                                    -PollIntervalSec $PollIntervalSec `
                                    -OutputFile $tempFile

            $status.PodStatuses = @() # ?? can't assign the array to podStatuses
            Write-Verbose "Pod statuses are $($podStatuses | ConvertTo-Json -Depth 5 -EnumsAsStrings)"
            $status.PodStatuses += $podStatuses
            $status.Running = ![bool]($podStatuses | Where-Object status -ne Running)
        } else {
            Write-Warning "No DeploymentSelector specified, not checking main pod"
        }
        Write-Verbose "PodStatuses: $($status.PodStatuses | Format-List | Out-String)"

        if ($DeploymentSelector -and !$status.Running) {
            $status.RollbackStatus = rollbackAndWarn -SkipRollbackOnError $SkipRollbackOnError -ReleaseName $ReleaseName -Msg "Release $ReleaseName had errors" -PrevVersion $prevVersion
        } else {
            $status.RollbackStatus = [RollbackStatus]::DeployedOk
        }
        Write-Output $status
    } catch {
        $err = $_
        if ($DeploymentSelector) {
            $status.RollbackStatus = rollbackAndWarn -SkipRollbackOnError $SkipRollbackOnError -ReleaseName $ReleaseName -Msg "Release $ReleaseName had errors" -PrevVersion $prevVersion
        }
        Write-Warning "Caught error. Following status may be incomplete"
        Write-Output $status
        Write-Error "$err`n$($err.ScriptStackTrace)"
    } finally {
        Pop-Location
        $script:ColorType = $prev
        Write-MyHost "Output was written to $tempFile"
    }
}