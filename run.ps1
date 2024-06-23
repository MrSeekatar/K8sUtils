#! pwsh
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
    [string] $NugetPassword = $env:nuget_password,
    [string[]] $tag = @(),
    [switch] $prerelease
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

foreach ($currentTask in $Tasks) {

    try {
        $prevPref = $ErrorActionPreference
        $ErrorActionPreference = "Stop"

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
                if (!$NugetPassword -or !$Repository) {
                    throw "NugetPassword and Repository parameters must be set"
                }
                executeSB -RelativeDir "K8sUtils" {
                    try {
                        if ($prerelease) {
                            Copy-Item K8sUtils.psd1 K8sUtils.psd1.bak -Force
                            (Get-Content K8sUtils.psd1 -Raw) -replace '# Prerelease = ''''', 'Prerelease = ''prelease''' | Set-Content K8sUtils.psd1 -Encoding 'UTF8' -NoNewline
                        }
                        Publish-Module -Repository $Repository -Path . -NuGetApiKey $NugetPassword
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
                    $result = Invoke-Pester -PassThru -Tag $tag
                    $i = 0
                    Write-Information ($result.tests | Where-Object { $i+=1; $_.executed -and !$_.passed } | Select-Object name, @{n='i';e={$i}},@{n='tags';e={$_.tag -join ','}}, @{n='Error';e={$_.ErrorRecord.DisplayErrorMessage -Replace [Environment]::NewLine,"" }} | Out-String)  -InformationAction Continue
                    Write-Information "Test results: are in `$test_results" -InformationAction Continue
                    $global:test_results = $result
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
    finally {
        $ErrorActionPreference = $prevPref
    }
}
