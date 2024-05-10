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
    [string] $K8sUtilsVersion
)

$currentTask = ""
$imageName = "minimal"

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

if ($Tasks -eq "ci") {
    $Tasks = @('CreateLocalNuget', 'Build', 'Test', 'Pack') # todo sample task expansion
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
                if (!$nuget_password) {
                    throw "nuget_password and K8sUtilsVersion must be set"
                }
                executeSB -RelativeDir "K8sUtils" {
                    $K8sUtilsVersion
                    Publish-Module -Repository Loyal -Path . -NuGetApiKey $nuget_password
                }
            }
            'upgradeHelm' {
                executeSB -RelativeDirectory DevOps/Helm {
                    Import-Module ../../K8sUtils/K8sUtils.psm1 -Force
                    $parms = @()
                    if ($DryRun) {
                        $parms += "--dry-run"
                    }
                    helm upgrade --install test . -f minimal1_values.yaml --namespace default @parms
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
