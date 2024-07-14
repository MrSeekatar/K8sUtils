$script:ColorType = "ANSI"
$script:HeaderPrefix = ""
$script:FooterPrefix = ""
$script:Dashes = 30

function Get-TempLogFile($prefix = "k8s-") {
    $temp = [System.IO.Path]::GetTempFileName()
    $ret = Join-Path( Split-Path -Path $temp -Parent) "$prefix$(Split-Path -Path $temp -Leaf)"
    $script:OutputFile = $ret
    return $ret
}

$script:OutputFile = Get-TempLogFile

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
        [string] $OutputFile = $script:OutputFile,
        [string] $HeaderPrefix = $script:HeaderPrefix
    )
    $headerMessage = $LogLevel -eq "error" ? "ERROR" : ""
    $prefix = $LogLevel -eq "error" ? "" : $HeaderPrefix
    Write-Status -Msg $headerMessage -LogLevel $LogLevel -ColorType $ColorType -Char '╒═╕' -OutputFile $OutputFile -Length 80
    Write-Status -Msg $msg -LogLevel normal -Length $Length -ColorType ANSI -Char '─' -OutputFile $OutputFile -Prefix $prefix -NoDate

    $script:headerLogLevel = $LogLevel
    $script:headerLength = $Length
    $script:headerColorType = $ColorType
    $script:headerOutputFile = $OutputFile
}

function Write-Footer() {
    [CmdletBinding()]
    param(
        [string]$msg,
        [string] $FooterPrefix = $script:FooterPrefix
    )
    $prefix = $script:headerLogLevel -eq "error" ? "" : $FooterPrefix
    Write-Status -Msg $msg -LogLevel normal -Length $script:headerLength -ColorType $script:headerColorType -Char '─' -OutputFile $script:headerOutputFile -Prefix $prefix -NoDate
    Write-Status -LogLevel $script:headerLogLevel -ColorType $script:headerColorType -Char '╘═╛' -OutputFile $script:headerOutputFile -Length 80

    # Write-Status -Msg $msg -LogLevel normal -Length $Length -Suffix "`n" -ColorType $ColorType -Char '╘═╛' -OutputFile $OutputFile -Prefix $prefix -NoDate
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
        [string] $Char = '─',
        [string] $OutputFile = $script:OutputFile,
        [switch] $NoDate
    )

    process {
        Set-StrictMode -Version Latest

        if ($NoDate) {
            $date = ""
        } else {
            $date = "$((Get-Date).ToString("u")) "
        }

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

        # if ($VerbosePreference -eq 'Continue') {
        #     "${Prefix}${date}${msg}${Suffix}" | Tee-Object $OutputFile -Append | Write-Verbose
        # } else {
        "${Prefix}${date}${msg}${Suffix}" | Write-Plain
        # }
    }
}

function Write-Plain() {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)]
        [string]$msg,
        [string] $OutputFile = $script:OutputFile
    )

    process {
        $msg | Tee-Object $OutputFile -Append | Write-MyHost
    }
}