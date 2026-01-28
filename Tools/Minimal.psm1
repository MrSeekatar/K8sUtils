param( [bool] $Quiet = $false, [bool] $LogVerboseStackArg = $false, [bool] $UseThreadJobsArg = $true )

$env:invokeHelmAllowLowTimeouts=1

$exports = @()
Get-ChildItem $PSScriptRoot\*.ps1 | Where-Object { $_ -notlike '*.tests.ps1' } | ForEach-Object { . $_; $exports += $_.BaseName }

Export-ModuleMember -Function $exports -Alias '*'

if (!$Quiet) {
    $me = $MyInvocation.MyCommand.Name -split '\.' | Select-Object -First 1
    Write-Information "`n$me loaded. Use help <command> -Full for help.`n`nCommands:" -InformationAction Continue
    $exports | Write-Information -InformationAction Continue

    Write-Information "`nUse Import-Module $me -ArgumentList `$true to suppress this message`n" -InformationAction Continue
}

if (!(Get-Module K8sUtils -ErrorAction Ignore)) {
    Write-Warning "Must import K8sUtils before using this module."
}