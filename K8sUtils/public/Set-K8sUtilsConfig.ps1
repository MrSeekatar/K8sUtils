function Set-K8sUtilsConfig {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions','', Justification = 'Just setting variables')]
    [CmdletBinding()]
    param (
        [ValidateSet("None","ANSI","DevOps")]
        [string] $ColorType
    )
    if ($ColorType) {
        $script:ColorType = $ColorType
        $script:HeaderPrefix = ">> "
        $script:FooterPrefix = "<< "
    } elseif (Test-Path env:TF_BUILD) {
        $script:ColorType = "DevOps"
        $script:HeaderPrefix = "##[group] 👈 CLICK ▸ TO EXPAND "
        $script:FooterPrefix = "##[endgroup]"
        $script:AddDate = $false
    }
}
