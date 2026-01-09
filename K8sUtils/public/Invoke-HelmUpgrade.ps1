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

.PARAMETER LogFileFolder
If specified, pod logs will be written to this folder

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
                    -SkipRollbackOnError

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
                     -DeploymentSelector app=hrabuilder-api

Do a Helm upgrade of a hra builder to dev


#>
function Invoke-HelmUpgrade {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingCmdletAliases', '', Justification = 'Locally helm is an alias')]
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
        [ValidateSet("None", "ANSI", "DevOps")]
        [string] $ColorType = $script:ColorType,
        [string] $LogFileFolder,
        [switch] $Quiet
    )
    Set-StrictMode -Version Latest
    $ErrorActionPreference = "Stop"

    $minPreHookTimeoutSecs = 120
    $minPodTimeoutSecs = 180

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
    if ($DebugPreference -eq "Continue") {
        $parms += "--debug"
    }
    if (!$Quiet) {
        Write-Header -Msg "Invoke-HelmUpgrade parameters"
        Write-Plain "Invoke-HelmUpgrade parameters:"
        Write-Plain "    ValueFile: $ValueFile"
        Write-Plain "    ChartName: $ChartName"
        Write-Plain "    ReleaseName: $ReleaseName"
        Write-Plain "    DeploymentSelector: $DeploymentSelector"
        Write-Plain "    Chart: $Chart"
        Write-Plain "    ChartVersion: $ChartVersion"
        Write-Plain "    Namespace: $Namespace"
        Write-Plain "    PreHookJobName: $PreHookJobName"
        Write-Plain "    PodTimeoutSecs: $PodTimeoutSecs"
        Write-Plain "    PreHookTimeoutSecs: $PreHookTimeoutSecs"
        Write-Plain "    PollIntervalSec: $PollIntervalSec"
        Write-Plain "    SkipRollbackOnError: $SkipRollbackOnError"
        Write-Plain "    DryRun: $DryRun"
        Write-Plain "    ColorType: $ColorType"
        Write-Plain "    Helm extra params $($parms -join " ")"
        Write-Footer
    }


    if (!$env:invokeHelmAllowLowTimeouts) {
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
    $prevVersion = 0
    $upgradeExit = 9
    $prevInfoPref = $InformationPreference
    $InformationPreference = [System.Management.Automation.ActionPreference]::Continue

    try {
        $hookMsg = $PreHookJobName ? " waiting ${PreHookTimeoutSecs}s prehook job '$PreHookJobName'" : ""

        Write-VerboseStatus "helm status --namespace $Namespace $ReleaseName -o json"
        $prevReleaseVersion = helm status --namespace $Namespace $ReleaseName -o json | ConvertFrom-Json -Depth 10 -AsHashtable # AsHashTable allows for duplicate keys in env, etc.
        if ($prevReleaseVersion -and ($prevReleaseVersion.ContainsKey('version'))) {
            $prevVersion = $prevReleaseVersion.version
            Write-VerboseStatus "Previous version of $ReleaseName was $prevVersion"
        }
        "helm upgrade $ReleaseName $Chart --install -f $ValueFile --reset-values --timeout ${PreHookTimeoutSecs}s --namespace $Namespace $($parms -join " ")" | Write-MyHost

        if ($DryRun) {
            Write-Status "Doing a helm dry run. Helm output and manifests follow."
        } else {
            Write-Header -Msg "Helm upgrade$hookMsg" -HeaderPrefix ""
        }
        $getPodJob = $null
        if (!$DryRun -and $PreHookJobName) {
            $statusVar = Get-Variable status
            $startTime = (Get-CurrentTime ([TimeSpan]::FromSeconds(-5))) # start a few seconds back to avoid very close timing

            $newWay = $false
            if ($newWay) {
                $getPodJob = Get-PreHookJob -PreHookJobName $PreHookJobName `
                    -Namespace $Namespace `
                    -LogFileFolder $LogFileFolder `
                    -StartTime $startTime `
                    -PreHookTimeoutSecs $PreHookTimeoutSecs `
                    -Status $status `
                    -InformationPreference $InformationPreference `
                    -VerbosePreference $VerbosePreference `
                    -DebugPreference $DebugPreference
            } else {
                $module = Join-Path $PSScriptRoot ../K8sUtils.psd1
                $getPodJob = Start-ThreadJob -ArgumentList $PreHookJobName, $Namespace, $LogFileFolder, $startTime, $PreHookTimeoutSecs, $module `
                    -ScriptBlock {
                    param($PreHookJobName, $Namespace, $LogFileFolder, $startTime, $PreHookTimeoutSecs, $module)
                    $ErrorActionPreference = "Stop"
                    Set-StrictMode -Version Latest

                    $inThreadPollIntervalSec = 1
                    $status = ($using:statusVar).Value
                    $InformationPreference = $using:InformationPreference
                    $VerbosePreference = $using:VerbosePreference
                    $DebugPreference = $using:DebugPreference

                    try {
                        Import-Module $module -ArgumentList $true -Verbose:$false
                        Write-Verbose "In thread. Loaded K8sUtil version $((Get-Module K8sUtils).Version). LogFileFolder is '$LogFileFolder'"

                        $hookStatus = Get-PodStatus -Selector "job-name=$PreHookJobName" `
                            -Namespace $Namespace `
                            -TimeoutSec $PreHookTimeoutSecs `
                            -PollIntervalSec $inThreadPollIntervalSec `
                            -PodType PreInstallJob `
                            -LogFileFolder $LogFileFolder
                        Write-Debug "Prehook status is $($hookStatus | ConvertTo-Json -Depth 5 -EnumsAsStrings)"
                        if ($hookStatus -is "array" ) {
                            Write-Warning "Multiple hook statuses returned:`n$($hookStatus  | ConvertTo-Json -Depth 5 -EnumsAsStrings)" # so we can see the status
                        }
                        $status.PreHookStatus = $hookStatus | Select-Object -Last 1 # get the last status, in case it was a job
                        if ($status.PreHookStatus.PodName -eq '<no pods found>') {
                            $events = Get-JobPodEvent -JobName $PreHookJobName -Since $startTime
                            if ($events) {
                                $errors = Write-K8sEvent -Name "$PreHookJobName's pod" `
                                    -Prefix "PreHookJob" `
                                    -Events $events `
                                    -LogLevel error `
                                    -PassThru
                                $status.PreHookStatus.LastBadEvents = $errors
                                Write-Debug "Prehook job '$PreHookJobName' events: $($status.PreHookStatus.LastBadEvents | ConvertTo-Json -Depth 5 -EnumsAsStrings)"
                            } else {
                                Write-Verbose "No events found for prehook job '$PreHookJobName' since $startTime"
                            }
                        }
                    } catch {
                        Write-Error "Error getting prehook pod status: $_`n$($_.ScriptStackTrace)"
                    }
                }
                Write-Verbose "Prehook jobId is $($getPodJob.Id)"
            }
        }

        $upgradeExitVar = Get-Variable upgradeExit

        $helmJob = Start-ThreadJob -ScriptBlock {
            param($ReleaseName, $Chart, $ValueFile, $PreHookTimeoutSecs, $Namespace, $parms)
            $ErrorActionPreference = "Stop"
            Set-StrictMode -Version Latest

            # Helm's default timeout is 5 minutes. This doesn't return until preHook is done
            "Start upgrade $((Get-Date).ToString("u"))"
            helm upgrade --install $ReleaseName $Chart -f $ValueFile --reset-values --timeout "${PreHookTimeoutSecs}s" --namespace $Namespace @parms 2>&1
            "End upgrade $((Get-Date).ToString("u"))"

            ($using:upgradeExitVar).Value = $LASTEXITCODE
        } -ArgumentList $ReleaseName, $Chart, $ValueFile, $PreHookTimeoutSecs, $Namespace, $parms
        Write-Verbose "Helm jobId is $($helmJob.Id)"

        if ($DryRun) {
            Receive-Job $helmJob -Wait -AutoRemoveJob | Write-MyHost
            Write-Verbose "Dry run job receive completed"
            return
        }

        Write-Verbose "Getting helm output"
        Receive-Job $helmJob -Wait -AutoRemoveJob | Write-MyHost
        Write-Verbose "Helm job receive completed"
        if ($upgradeExit -eq 0) {
            Write-Footer "End Helm upgrade OK. (exit code $upgradeExit)" -FooterPrefix ""
        } else {
            Write-Footer "Helm upgrade exited with: $upgradeExit" -FooterPrefix ""
            Write-Status "👆 Check Helm output for error message 👆" -LogLevel Error
        }
        if ($null -ne $getPodJob) {
            Write-Verbose "Getting prehook job output"
            Receive-Job $getPodJob -Wait -AutoRemoveJob | Write-MyHost
            Write-Verbose "Get prehook job receive completed"
        } else {
            Write-Verbose  "No getPodJob to receive"
        }

        if ($upgradeExit -ne 0 -or ($status.PreHookStatus -and $status.PreHookStatus.Status -ne [Status]::Completed)) {
            $status.Running = $false
            if ($status.PreHookStatus -and
                $status.PreHookStatus.Status -eq [Status]::Running ) {
                # timeout
                Write-VerboseStatus "Helm upgrade failed, setting prehook status to timeout"
                $status.PreHookStatus.Status = [Status]::Timeout
            }
            $status.RollbackStatus = rollbackAndWarn -SkipRollbackOnError $SkipRollbackOnError `
                -releaseName $ReleaseName `
                -msg "Helm upgrade got last exit code $upgradeExit" `
                -prevVersion $prevVersion
            Write-Output $status
            $upgradeExit = 9
            return
        }


        if ($DeploymentSelector) {
            $podStatuses = Get-DeploymentStatus -TimeoutSec $PodTimeoutSecs `
                -Namespace $Namespace `
                -Selector $DeploymentSelector `
                -PollIntervalSec $PollIntervalSec `
                -LogFileFolder $LogFileFolder

            $status.PodStatuses = @() # ?? can't assign the array to podStatuses
            Write-Debug "Pod statuses are $($podStatuses | ConvertTo-Json -Depth 5 -EnumsAsStrings)"
            $status.PodStatuses += $podStatuses
            $status.Running = ![bool]($podStatuses | Where-Object status -NE Running)
        } else {
            Write-Status "No DeploymentSelector specified, not checking main pod. Ok if this is a job"
        }
        Write-VerboseStatus "PodStatuses: $($status.PodStatuses | Format-List | Out-String)"

        if ($DeploymentSelector -and !$status.Running) {
            $status.RollbackStatus = rollbackAndWarn -SkipRollbackOnError $SkipRollbackOnError -ReleaseName $ReleaseName -Msg "Release '$ReleaseName' had errors" -PrevVersion $prevVersion
            $upgradeExit = 9
        } else {
            $status.RollbackStatus = [RollbackStatus]::DeployedOk
        }
        Write-Output $status
    } catch {
        $err = $_
        if ($DeploymentSelector) {
            Write-Warning "Rolling back due to error in catch block"
            Write-Warning "Exception: $_`n$($_.ScriptStackTrace)"
            $status.RollbackStatus = rollbackAndWarn -SkipRollbackOnError $SkipRollbackOnError -ReleaseName $ReleaseName -Msg "Release '$ReleaseName' had errors" -PrevVersion $prevVersion
        }
        Write-Warning "Caught error. Following status may be incomplete"
        Write-Output $status
        Write-Error "$err`n$($err.ScriptStackTrace)"
        $upgradeExit = 9
    } finally {
        $InformationPreference = $prevInfoPref
        $Global:LASTEXITCODE = $upgradeExit
        Pop-Location
        $script:ColorType = $prev
    }
}