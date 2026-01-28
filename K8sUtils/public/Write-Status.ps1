<#
.SYNOPSIS
Write out a log message

.DESCRIPTION
This replaces the Write-* cmdlets so order is preserved when running in jobs or thread jobs.

.PARAMETER msg
Message to write

.PARAMETER LogLevel
Log level, can be error, warning, ok, or normal

.PARAMETER Length
Length of the message line

.PARAMETER Prefix
Prefix to add before the message

.PARAMETER Suffix
Suffix to add after the message

.PARAMETER ColorType
Color type to use for the message, can be None, ANSI, or DevOps

.PARAMETER Char
Character to use for padding the message line
#>
function Write-Status() {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)]
        [string]$msg = "",
        [ValidateSet("error", "warning", "ok", "normal")]
        [string] $LogLevel = "normal",
        [int]$Length = $script:Dashes,
        [string] $Prefix = "",
        [string] $Suffix = "",
        [ValidateSet("None", "ANSI", "DevOps")]
        [string] $ColorType = $script:ColorType,
        [string] $Char = '─'
    )

    process {
        Set-StrictMode -Version Latest

        function mapLogLevel($date, $LogLevel, $Prefix) {
            if ($Prefix) {
                return ""
            }
            switch ($LogLevel) {
                "error" {
                    return "[${date}ERR]"
                }
                "warning" {
                    return "[${date}WRN]"
                }
                default {
                    return "[${date}INF]"
                }
            }
        }

        # if ($VerbosePreference -ne 'Continue') {
        $statusPrefix = $Prefix + (MapColor $LogLevel $ColorType)
        # }

        $date = $script:AddDate ? "$((Get-Date).ToString("u")) " : ""
        if ($Length -gt 0) {
            $maxWidth = try { $Host.UI.RawUI.WindowSize.Width } catch { 120 } # account for running a JobThread without a host
            $msgLen = ($statusPrefix + $date + $msg + $Suffix).Length
            if ($msgLen -lt $maxWidth) {
                $Length = [Math]::Min($Length, $maxWidth - $msgLen - 1)
                if ($Char.Length -eq 3) {
                    $msg = ($Char[1].ToString() * ($Length-2)) + $Char[2] + " $msg "
                } else {
                    $msg = ($Char * $Length) + " $msg "
                }
            }
        }

        "${statusPrefix}$(mapLogLevel $date $LogLevel $Prefix) ${msg}${Suffix}" | Write-Plain
    }
}
