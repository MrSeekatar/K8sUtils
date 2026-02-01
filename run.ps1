#! pwsh

<#
.SYNOPSIS
Run tasks associated with this repo. Use tab to cycle through them

.EXAMPLE
./run.ps1 test

Run all tests against Rancher Desktop (default)

.EXAMPLE
./run.ps1 test -tag t2 -KubeContext widget-aks-test-sc -Registry widget.azurecr.io

Run test t2 against AKS
#>
[CmdletBinding()]
param (
    [ArgumentCompleter({
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
            $runFile = (Join-Path (Split-Path $commandAst -Parent) run.ps1)
            if (Test-Path $runFile) {
                Get-Content $runFile |
                Where-Object { $_ -match "^\s+'([\w+-]+)' {" } |
                ForEach-Object {
                    if ( !($fakeBoundParameters[$parameterName]) -or
                            (($matches[1] -notin $fakeBoundParameters.$parameterName) -and
                             ($matches[1] -like "$wordToComplete*"))
                    ) {
                        $matches[1]
                    }
                }
            }
        })]
    [string[]] $Tasks,
    [switch] $Wait,
    [switch] $DryRun,
    [string] $K8sUtilsVersion,
    [string] $Repository,
    [string] $NuGetApiKey = $env:nuget_password,
    [string[]] $tag = @(),
    [switch] $prerelease,
    [Alias("context")]
    [Alias("kube-context")]
    [string] $KubeContext = "rancher-desktop",
    [string] $Registry,
    [switch] $UseThreadJobsInTests
)

$currentTask = ""

# execute a script, checking lastexit code
function executeSB {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock] $ScriptBlock,
        [string] $RelativeDirectory = "",
        [string] $TaskName = $currentTask
    )
    Push-Location (Join-Path $PSScriptRoot $RelativeDirectory)

    try {
        $global:LASTEXITCODE = 0

        Invoke-Command -ScriptBlock $ScriptBlock

        if ($LASTEXITCODE -ne 0) {
            throw "Error executing command '$TaskName', last exit $LASTEXITCODE"
        }
    }
    finally {
        Pop-Location
    }
}

$prevContext = kubectl config current-context
$prevPref = $ErrorActionPreference

function Invoke-Test {
    param (
        [Parameter(Mandatory)]
        [string] $testFile
    )
    if ($Registry) {
        $PSDefaultParameterValues['Deploy-*:registry'] = $Registry
    }

    try {
        $global:k8sutils_last_test_errors = @()
        $env:K8sUtils_UseThreadJobs = [bool]$UseThreadJobsInTests
        if (!(Get-Command -Name docker -ErrorAction SilentlyContinue) -or
            !(Get-Command -Name helm -ErrorAction SilentlyContinue) -or
            !(Get-Command -Name Invoke-Pester -ErrorAction SilentlyContinue) ) {
            throw "docker, helm, and Invoke-Pester must be installed for these tests"
        }
        $images = docker images --format json | ConvertFrom-json -depth 4
        if (!($images | Where-Object { $_.Repository -eq 'minimal' })) {
            throw "Must have a minimal image for these tests. See README.md to build it."
        }
        if (!($images | Where-Object { $_.Repository -eq 'init-app' })){
            throw "Must have a init-app image for these tests. See README.md to build it."
        }
        $result = Invoke-Pester -PassThru -Tag $tag -Path $testFile
        $i = 0
        $errors = $result.tests | Where-Object { $i+=1; $_.executed -and !$_.passed }
        Write-Information ($errors | Select-Object name, @{n='i';e={$i-1}},@{n='tags';e={$_.tag -join ','}}, @{n='Error';e={$_.ErrorRecord.DisplayErrorMessage -Replace [Environment]::NewLine,"\n" }} | Out-String -Width 1000) -InformationAction Continue
        Write-Information "Test results: are in `$k8sutils_test_results" -InformationAction Continue
        $global:k8sutils_last_test_errors = $errors
        $global:k8sutils_test_results = $result
        Remove-Item env:K8sUtils_UseThreadJobs -ErrorAction SilentlyContinue
    } finally {
        if ($Registry) {
            $PSDefaultParameterValues.Remove('Deploy-*:registry')
        }
    }
}

try {
    $ErrorActionPreference = "Stop"
    kubectl config use-context $KubeContext

    foreach ($currentTask in $Tasks) {

        "-------------------------------"
        "Starting $currentTask"
        "-------------------------------"

        switch ($currentTask) {
            'applyManifests' {
                executeSB -RelativeDirectory DevOps/Kubernetes {
                    # wildcards give an error (*.y*)
                    kubectl apply -f .
                }
            }
            'publishK8sUtils' {
                if (!$NuGetApiKey -or !$Repository) {
                    throw "NuGetApiKey and Repository parameters must be set"
                }
                "Using password that starts with $($NuGetApiKey.Substring(0, 3)) and repository $Repository"
                executeSB -RelativeDir "K8sUtils" {
                    try {
                        if ($prerelease) {
                            Copy-Item K8sUtils.psd1 K8sUtils.psd1.bak -Force
                            Update-ModuleManifest K8sUtils.psd1 -Prerelease "prerelease$(Get-Date -Format 'MMddHHmm')"
                        }
                        Publish-Module -Repository $Repository -Path . -NuGetApiKey $NuGetApiKey
                    } finally {
                        if ($prerelease) {
                            Copy-Item K8sUtils.psd1.bak K8sUtils.psd1
                            Remove-Item K8sUtils.psd1.bak -ErrorAction SilentlyContinue
                        }
                    }
                }
            }
            'test' {
                executeSB  {
                    Invoke-Test Tools/MinimalDeploy.tests.ps1
                }
            }
            'testJob' {
                executeSB  {
                    Invoke-Test Tools/JobDeploy.tests.ps1
                }
            }
            'testJobK8s' {
                executeSB  {
                    Invoke-Test Tools/JobDeployK8s.tests.ps1
                }
            }
            'upgradeHelm' {
                executeSB -RelativeDirectory DevOps/Helm {
                    Import-Module ../../K8sUtils/K8sUtils.psm1 -Force
                    $parms = @()
                    if ($DryRun) {
                        $parms += "--dry-run"
                    }
                    helm upgrade --install test . -f minimal_values.yaml --namespace default @parms
                }
            }
            'uninstallHelm' {
                executeSB -RelativeDirectory DevOps/Helm {
                    helm uninstall test
                }
            }
            default {
                throw "Invalid task name $currentTask"
            }
        }
    }
}
finally {
    $ErrorActionPreference = $prevPref
    kubectl config use-context $prevContext
}
