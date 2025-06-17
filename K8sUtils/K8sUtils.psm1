param( [bool] $Quiet = $false )

if (!(Get-Command "kubectl" -ErrorAction Ignore) -or !(Get-Command "helm" -ErrorAction Ignore)) {
    throw "kubectl and helm must be installed and in the PATH. Correct and reload the module."
}

Get-ChildItem $PSScriptRoot\private\*.ps1 | ForEach-Object { . $_ }
$exports = @()
Get-ChildItem $PSScriptRoot\public\*.ps1 | ForEach-Object { . $_; $exports += $_.BaseName }
$exports += Get-Alias | Where-Object source -eq 'k8sutils' | Select-Object -ExpandProperty Name
# see psd1 Export-ModuleMember -Function $exports -Alias '*'

Set-K8sUtilsConfig

if (!$Quiet -and !(Test-Path env:TF_BUILD)) {
    $me = $MyInvocation.MyCommand.Name -split '\.' | Select-Object -First 1
    Write-Information "`n$me loaded. Use help <command> -Full for help.`n`nCommands:" -InformationAction Continue
    $exports | Sort-Object | Write-Information -InformationAction Continue

    Write-Information "`nUse Import-Module $me -ArgumentList `$true to suppress this message`n" -InformationAction Continue
}
