function Set-K8sUtilsConfig {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions','', Justification = 'Just setting variables')]
    [CmdletBinding()]
    param (
        [ValidateSet("None","ANSI","DevOps")]
        [string] $ColorType
    )
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
