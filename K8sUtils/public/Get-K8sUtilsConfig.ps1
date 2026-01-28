<#
.SYNOPSIS
Get the current configuration settings for K8sUtils

#>
function Get-K8sUtilsConfig {
    [CmdletBinding()]
    param ()
    @{
        UtcOffset = $script:UtcOffset
        LogVerboseStack = $script:LogVerboseStack
        UseThreadJobs = $script:UseThreadJobs
        LoggingSettings = @{
            ColorType = $script:ColorType
            HeaderPrefix = $script:HeaderPrefix
            FooterPrefix = $script:FooterPrefix
            AddDate = $script:AddDate
        }
    }
}
