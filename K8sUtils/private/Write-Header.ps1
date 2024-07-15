$script:ColorType = "ANSI"
$script:HeaderPrefix = ""
$script:FooterPrefix = ""
$script:AddDate = $true
$script:Dashes = 30

function Write-MyHost {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Write-Information need ANSI resets')]
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true)]
        [object] $msg
    )
    process {
        $suffix = $script:ColorType -eq "ANSI" ? $PSStyle.Reset : ""
        Write-Information "$msg$suffix" -InformationAction Continue
        # Write-Host $msg
    }
}

function MapColor([ValidateSet("error", "warning", "ok", "normal")] $LogLevel,
    [ValidateSet("None", "ANSI", "DevOps")] [string] $ColorType) {

    switch ($ColorType) {
        "ANSI" {
            switch ($LogLevel) {
                "error" {
                    return $PSStyle.Formatting.Error
                }
                "warning" {
                    return $PSStyle.Formatting.Warning
                }
                "ok" {
                    return $PSStyle.Formatting.FormatAccent
                }
                default {
                    return ""
                }
            }
        }
        "DevOps" {
            switch ($LogLevel) {
                "error" {
                    return "##[error]"
                }
                "warning" {
                    return "##[warning]"
                }
                default {
                    ""
                }
            }
        }
        default {
            switch ($LogLevel) {
                "error" {
                    return " [ERR] "
                }
                "warning" {
                    return "[WRN]"
                }
                default {
                    return " [INF] "
                }
            }
        }
    }
}

function Write-Header() {
    [CmdletBinding()]
    param(
        [string]$msg,
        [ValidateSet("error", "warning", "ok", "normal")]
        [string] $LogLevel = "normal",
        [int]$Length = $script:Dashes,
        [ValidateSet("None", "ANSI", "DevOps")]
        [string] $ColorType = $script:ColorType,
        [string] $HeaderPrefix = $script:HeaderPrefix
    )
    $headerMessage = $LogLevel -eq "error" ? "ERROR" : ""
    $prefix = $LogLevel -eq "error" ? "" : $HeaderPrefix
    Write-Status -Msg $headerMessage -LogLevel $LogLevel -ColorType $ColorType -Char '╒═╕' -Length 80
    Write-Status -Msg $msg -LogLevel normal -Length $Length -ColorType ANSI -Char '─' -Prefix $prefix

    $script:headerLogLevel = $LogLevel
    $script:headerLength = $Length
    $script:headerColorType = $ColorType
}

function Write-Footer() {
    [CmdletBinding()]
    param(
        [string]$msg,
        [string] $FooterPrefix = $script:FooterPrefix
    )
    $prefix = $script:headerLogLevel -eq "error" ? "" : $FooterPrefix
    Write-Status -Msg $msg -LogLevel normal -Length $script:headerLength -ColorType $script:headerColorType -Char '─' -Prefix $prefix
    Write-Status -LogLevel $script:headerLogLevel -ColorType $script:headerColorType -Char '╘═╛' -Length 80
}

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

        function mapLogLevel($LogLevel) {
            switch ($LogLevel) {
                "error" {
                    return "ERR"
                }
                "warning" {
                    return "WRN"
                }
                default {
                    return "INF"
                }
            }
        }

        $date = $script:AddDate ? "$((Get-Date).ToString("u")) " : ""

        # if ($VerbosePreference -ne 'Continue') {
        $Prefix += (MapColor $LogLevel $ColorType)
        # }

        if ($Length -gt 0) {
            $maxWidth = $Host.UI.RawUI.WindowSize.Width
            $msgLen = ($Prefix + $date + $msg + $Suffix).Length
            if ($msgLen -lt $maxWidth) {
                $Length = [Math]::Min($Length, $maxWidth - $msgLen - 1)
                if ($Char.Length -eq 3) {
                    $msg = ($Char[1].ToString() * ($Length-2)) + $Char[2] + " $msg "
                } else {
                    $msg = ($Char * $Length) + " $msg "
                }
            }
        }

        "${Prefix}[${date}$(mapLogLevel $LogLevel)] ${msg}${Suffix}" | Write-Plain
    }
}

function Write-Plain() {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)]
        [string]$msg
    )

    process {
        $msg | Write-MyHost
    }
}