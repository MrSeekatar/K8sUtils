<#
.SYNOPSIS
Set some configuration settings for K8sUtils

.PARAMETER ColorType
Type of color to use for output, defaults to ANSI, can be None or DevOps

.PARAMETER OffsetMinutes
Number of minutes to offset UTC time used when finding events. ET would be -5*60. Default to -1 and uses local time offset.

.PARAMETER LogVerboseStack
Log stack traces for verbose messages

.PARAMETER UseThreadJobs
Use a separate job thread to monitor prehook pods
#>
function Set-K8sUtilsConfig {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions','', Justification = 'Just setting variables')]
    [CmdletBinding()]
    param (
        [ValidateSet("None","ANSI","DevOps")]
        [string] $ColorType,
        [int] $OffsetMinutes = -1,
        [switch] $LogVerboseStack,
        [switch] $UseThreadJobs
    )
    if ($OffsetMinutes -ge 0) {
        $script:UtcOffset = New-TimeSpan -Minutes $OffsetMinutes
    } else {
        $script:UtcOffset = [DateTimeOffset]::Now.Offset
    }
    $script:LogVerboseStack = [bool]$LogVerboseStack
    $script:UseThreadJobs = [bool]$UseThreadJobs

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
