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
How to colorize the output. Defaults to DevOps if TF_BUILD env var, otherwise ANSI colors. Can also set with Set-K8sUtilsConfig

.PARAMETER LogFileFolder
If specified, pod logs will be written to this folder

.PARAMETER Quiet
If set will not log out all the settings

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
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'Called functions supports ShouldProcess')]
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

    $prevInfoPref = $InformationPreference
    $InformationPreference = [System.Management.Automation.ActionPreference]::Continue

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
        Write-Plain "    Chart: $Chart"
        Write-Plain "    ChartName: $ChartName"
        Write-Plain "    ChartVersion: $ChartVersion"
        Write-Plain "    ColorType: $script:ColorType"
        Write-Plain "    DeploymentSelector: $DeploymentSelector"
        Write-Plain "    DryRun: $DryRun"
        Write-Plain "    Helm extra params $($parms -join " ")"
        Write-Plain "    Namespace: $Namespace"
        Write-Plain "    PodTimeoutSecs: $PodTimeoutSecs"
        Write-Plain "    PollIntervalSec: $PollIntervalSec"
        Write-Plain "    PreHookJobName: $PreHookJobName"
        Write-Plain "    PreHookTimeoutSecs: $PreHookTimeoutSecs"
        Write-Plain "    ReleaseName: $ReleaseName"
        Write-Plain "    SkipRollbackOnError: $SkipRollbackOnError"
        Write-Plain "    LogVerboseStack: $script:LogVerboseStack"
        Write-Plain "    UseThreadJobs: $script:UseThreadJobs"
        Write-Plain "    ValueFile: $ValueFile"
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

    try {
        $hookMsg = $PreHookJobName ? " waiting ${PreHookTimeoutSecs}s prehook job '$PreHookJobName'" : ""

        Write-VerboseStatus "helm status --namespace $Namespace $ReleaseName -o json"
        $prevReleaseVersion = helm status --namespace $Namespace $ReleaseName -o json | ConvertFrom-Json -Depth 10 -AsHashtable # AsHashTable allows for duplicate keys in env, etc.
        if ($prevReleaseVersion -and ($prevReleaseVersion.ContainsKey('version'))) {
            $prevVersion = $prevReleaseVersion.version
            Write-VerboseStatus "Previous version of $ReleaseName was $prevVersion"
        }

        if ($DryRun) {
            Write-Status "Doing a helm dry run. Helm output and manifests follow."
        } else {
            Write-Header -Msg "Helm upgrade$hookMsg" -HeaderPrefix ""
        }

        $getPodJob = $null
        if ($PreHookJobName -and !$DryRun -and $script:UseThreadJobs) {
            $getPodJob = Start-PreHookJobThread $PreHookJobName `
                -Namespace $Namespace `
                -LogFileFolder $LogFileFolder `
                -PreHookTimeoutSecs $PreHookTimeoutSecs `
                -Status $status
            for ($i = 0; !$script:jobThreadReady -and $i -lt 10; $i++) {
                Start-Sleep -Seconds 1 # give thread a moment to start
            }
            Write-Status "Waited $i seconds for prehook job thread to start"
        }

        # Helm's default timeout is 5 minutes. This doesn't return until preHook is done
        "helm upgrade --install $ReleaseName $Chart -f $ValueFile --reset-values --timeout  ${PreHookTimeoutSecs}s  --namespace $Namespace $($parms -join " ")" | Write-MyHost
        helm  upgrade --install $ReleaseName $Chart -f $ValueFile --reset-values --timeout "${PreHookTimeoutSecs}s" --namespace $Namespace @parms 2>&1 | Write-MyHost
        $upgradeExit = $LASTEXITCODE

        if ($DryRun) {
            return
        } elseif ($upgradeExit -eq 0) {
            Write-Footer "End Helm upgrade OK. (exit code $upgradeExit)" -FooterPrefix ""
        } else {
            Write-Footer "Helm upgrade exited with: $upgradeExit" -FooterPrefix ""
            Write-Status "👆 Check Helm output for error message 👆" -LogLevel Error
        }

        if ($null -ne $getPodJob) {
            Write-Header "Beginning of prehook job output"
            Receive-Job $getPodJob -Wait -AutoRemoveJob | Write-MyHost
            Write-Footer "End of prehook job output"
        } else {
            $startTime = (Get-CurrentTime ([TimeSpan]::FromSeconds(-5))) # start a few seconds back to avoid very close timing

            if ($PreHookJobName) {
                Get-PreHookJobStatus -PreHookJobName $PreHookJobName `
                -Namespace $Namespace `
                -LogFileFolder $LogFileFolder `
                -StartTime $startTime `
                -PreHookTimeoutSecs 1 `
                -PollIntervalSec $PollIntervalSec `
                -Status $status
            }
        }

        if ($upgradeExit -ne 0 -or ($status.PreHookStatus -and $status.PreHookStatus.Status -ne [Status]::Completed)) {
            $status.Running = $false
            if ($status.PreHookStatus -and
                $status.PreHookStatus.Status -eq [Status]::Running ) {
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
            $status.RollbackStatus = rollbackAndWarn -SkipRollbackOnError $SkipRollbackOnError -ReleaseName $ReleaseName -Msg "Release '$ReleaseName' is not running" -PrevVersion $prevVersion
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