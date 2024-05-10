function Set-K8sUtilsDefaults {
    [CmdletBinding()]
    param (
        [string] $LogFile,
        [ValidateSet("None","ANSI","DevOps")]
        [string] $ColorType
    )
    if ($LogFile) {
        $script:OutputFile = $LogFile
    }
    if ($ColorType) {
        $script:ColorType = $ColorType
        $script:HeaderPrefix = ">> "
        $script:FooterPrefix = "<< "
    } elseif (Test-Path env:TF_BUILD) {
        $script:ColorType = "DevOps"
        $script:HeaderPrefix = "##[group] 👈 Expand"
        $script:FooterPrefix = "##[endgroup]"
    }
}
