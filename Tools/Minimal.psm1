param( [bool] $Quiet = $false, [bool] $LogVerboseStack = $false, [bool] $UseThreadJobs = $true )

$env:invokeHelmAllowLowTimeouts=1

Import-Module $PSScriptRoot\..\K8sUtils\K8sUtils.psd1 -ArgumentList $true, $LogVerboseStack, $UseThreadJobs -Force
Write-Information "Loaded K8sUtils Module in Minimal.psm1" -InformationAction Continue

$exports = @()
Get-ChildItem $PSScriptRoot\*.ps1 | Where-Object { $_ -notlike '*.tests.ps1' } | ForEach-Object { . $_; $exports += $_.BaseName }

Export-ModuleMember -Function $exports -Alias '*'

if (!$Quiet) {
    $me = $MyInvocation.MyCommand.Name -split '\.' | Select-Object -First 1
    Write-Information "`n$me loaded. Use help <command> -Full for help.`n`nCommands:" -InformationAction Continue
    $exports | Write-Information -InformationAction Continue

    Write-Information "`nUse Import-Module $me -ArgumentList `$true to suppress this message`n" -InformationAction Continue
}
