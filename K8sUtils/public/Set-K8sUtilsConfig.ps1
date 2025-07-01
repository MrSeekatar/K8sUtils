<#
.SYNOPSIS
Set some configuration settings for K8sUtils

.PARAMETER ColorType
Type of color to use for output, defaults to ANSI, can be None or DevOps

.PARAMETER OffsetMinutes
Number of minutes to offset UTC time.
#>
function Set-K8sUtilsConfig {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions','', Justification = 'Just setting variables')]
    [CmdletBinding()]
    param (
        [ValidateSet("None","ANSI","DevOps")]
        [string] $ColorType,
        [int] $OffsetMinutes = 0.0
    )
    $script:UtcOffset = New-TimeSpan -Minutes $OffsetMinutes

    if ($ColorType -eq "None" -or $env:NO_COLOR -eq "1") {
        $script:ColorType = "None"
        $script:HeaderPrefix = ">> "
        $script:FooterPrefix = "<< "
    } elseif ($ColorType -eq "DevOps" -or (Test-Path env:TF_BUILD)) {
        $script:ColorType = "DevOps"
        $script:HeaderPrefix = "##[group] 👈 CLICK ▸ TO EXPAND "
        $script:FooterPrefix = "##[endgroup]"
        $script:AddDate = $false
    } else {
        $script:ColorType = "ANSI"
        $script:HeaderPrefix = ""
        $script:FooterPrefix = ""
    }
}
