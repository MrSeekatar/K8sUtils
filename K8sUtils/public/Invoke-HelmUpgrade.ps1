<#
.SYNOPSIS
Invoke helm upgrade using helper scripts to catch errors, and rollback

.PARAMETER ValueFile
Name of the values file to use

.PARAMETER ChartName
Name of the chart to upgrade

.PARAMETER ReleaseName
Name of the helm release

.PARAMETER Chart
Path to the chart folder or tgz, or url, defaults to .

.PARAMETER Namespace
K8s namespace to use, defaults to default

.PARAMETER PreHookJobName
If set runs the helm prehook job

.PARAMETER HelmSet
Any additional values to set with --set for helm

.PARAMETER HelmSetJson
Any additional values to set with --set-json for helm

.PARAMETER PodTimeoutSecs
Timeout in seconds for waiting on the pods. Defaults to 600

.PARAMETER PreHookTimeoutSecs
Timeout in seconds for waiting on the prehook job to complete, if PreHookJobName is set. Defaults to 60

.PARAMETER SkipRollbackOnError
If set, don't do a helm rollback on error

.PARAMETER DryRun
If set, don't actually do the helm upgrade

.PARAMETER NoColor
If set, don't use color in output

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

Invoke-HelmUpgrade -ValueFile "./new-values.yml" `
                    -ChartName 'loyal-app' `
                    -Chart '~/code/DevOps/helm-charts/internal-charts/loyal-app-template' `
                    -ReleaseName "backendtemplate-api" `
                    -PreHookJobName "backendtemplate-api" `
                    -PreHookTimeoutSecs 120 `
                    -DeploymentSelector app=backendtemplate-api `
                    -SkipRollbackOnError -Verbose

Do a Helm upgrade of a backend template to test with a Perses prehook job

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
                     -ChartName 'loyal-app' `
                     -Chart '~/code/DevOps/helm-charts/internal-charts/loyal-app-template' `
                     -ReleaseName "hrabuilder-api" `
                     -DeploymentSelector app=hrabuilder-api `
                      -Verbose

Do a Helm upgrade of a hra builder to dev


#>
function Invoke-HelmUpgrade {
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

        $currentReleaseVersion = helm status --namespace $Namespace $ReleaseName -o json | ConvertFrom-Json
        if (!$currentReleaseVersion -or !(Get-Member -InputObject $currentReleaseVersion -Name version -MemberType Property)) {
            Write-Status "Unexpected response from helm status, not rolling back" -LogLevel warning -Char '-'
            Write-Warning ($currentReleaseVersion | ConvertTo-Json -Depth 5 -EnumsAsStrings)
            return
        }
        Write-Verbose "Current version of $ReleaseName is $($currentReleaseVersion.version)"
        if (!$currentReleaseVersion -or $currentReleaseVersion.version -eq $prevVersion) {
            Write-Status "No change in release $ReleaseName, not rolling back" -LogLevel warning -Char '-'
            # throw "$msg, no change"
            Write-Warning "$msg, no change"
            return
        }

        if (!$SkipRollbackOnError) {
            Write-Header "Rolling back release $ReleaseName due to errors" -LogLevel Error
            $errFile = Get-TempLogFile
            helm rollback $ReleaseName 2>&1 | Tee-Object $errFile | Write-Host
            Get-Content $errFile -Raw | Out-File $tempFile -Append
            $exit = $LASTEXITCODE
            $content = Get-Content $errFile -Raw
            $content | Out-File $OutputFile -Append
            if ($exit -ne 0 -and ($content -like '*Error: release has no 0 version*' -or $content -like '*Error: release: not found*')) {
                Write-Verbose "Last exit code on rollback was $exit. Contents of ${errFile}:`n$content"
                Write-Status "helm rollback failed, trying uninstall" -LogLevel Error -Char '-'
                helm uninstall $ReleaseName | Out-File $OutputFile -Append
            }
            Write-Footer "End rolling back release $ReleaseName due to errors"
            Remove-Item $errFile -ErrorAction SilentlyContinue
            # throw "$msg, rolled back"
            Write-Warning "$msg, rolled back"
        } else {
            # throw "$msg, but not rolling back since -SkipRollbackOnError was specified"
            Write-Warning "$msg, but not rolling back since -SkipRollbackOnError was specified"
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
    Write-Verbose "Params $($parms -join " ")"

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

    try {
        $hookMsg = $PreHookJobName ? " waiting ${PreHookTimeoutSecs}s prehook job '$PreHookJobName'" : ""

        $prevReleaseVersion = helm status --namespace $Namespace $ReleaseName -o json | ConvertFrom-Json
        if ($prevReleaseVersion -and (Get-Member -InputObject $prevReleaseVersion -Name version -MemberType Property)) {
            $prevVersion = $prevReleaseVersion.version
            Write-Verbose "Previous version of $ReleaseName was $prevVersion"
        } else {
            $prevVersion = 0
        }
        "helm upgrade $ReleaseName $Chart --install -f $ValueFile --reset-values --timeout ${PreHookTimeoutSecs}s --namespace $Namespace $($parms -join " ")" | Tee-Object $tempFile -Append | Write-Host

        Write-Header "Helm upgrade$hookMsg"
        # Helm's default timeout is 5 minutes. This doesn't return until preHook is done
        helm upgrade --install $ReleaseName $Chart -f $ValueFile --reset-values --timeout "${PreHookTimeoutSecs}s" --namespace $Namespace @parms 2>&1 | Tee-Object $tempFile -Append | Write-Host
        $upgradeExit = $LASTEXITCODE
        Write-Footer "End Helm upgrade (exit code $upgradeExit)"

        if ($DryRun) {
            return
        }
        $status = [ReleaseStatus]::new($ReleaseName)

        if ($PreHookJobName) {
            $x = Get-PodStatus -Selector "job-name=$PreHookJobName" `
                                                        -Namespace $Namespace `
                                                        -OutputFile $tempFile `
                                                        -TimeoutSec $PreHookTimeoutSecs `
                                                        -IsJob
            Write-Verbose "Prehook status is $($x | ConvertTo-Json -Depth 5 -EnumsAsStrings)"
            $status.PreHookStatus = $x

            if ($upgradeExit -ne 0) {
                $status.Running = $false
                Write-Output $status
                rollbackAndWarn $SkipRollbackOnError $ReleaseName "Helm upgrade got last exit code $upgradeExit" $prevVersion
                return
            }
        }

        $podStatuses = Get-DeploymentStatus -TimeoutSec $PodTimeoutSecs `
                                   -Namespace $Namespace `
                                   -Selector $DeploymentSelector `
                                   -PollIntervalSec $PollIntervalSec `
                                   -OutputFile $tempFile

        $status.PodStatuses = @() # ?? can't assign the array to podStatuses
        Write-Verbose "Pod statuses are $($podStatuses | ConvertTo-Json -Depth 5 -EnumsAsStrings)"
        $status.PodStatuses += $podStatuses
        $status.Running = ![bool]($podStatuses | Where-Object status -ne Running)

        Write-Verbose "PodStatuses: $($status.PodStatuses | Format-List | Out-String)"

        Write-Output $status
        if (!$status.Running) {
            rollbackAndWarn $SkipRollbackOnError $ReleaseName "Release $ReleaseName had errors" $prevVersion
        }
    } catch {
        Write-Error "$_`n$($_.ScriptStackTrace)"
    } finally {
        Pop-Location
        $script:ColorType = $prev
        Write-Host "Output was written to $tempFile"
    }
}