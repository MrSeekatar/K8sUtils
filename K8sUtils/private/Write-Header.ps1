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

function MapColor([ValidateSet("error", "warning", "ok","normal")] $LogLevel,
                  [ValidateSet("None","ANSI","DevOps")] [string] $ColorType) {

    switch ($ColorType) {
        "ANSI" {
            switch ($LogLevel) {
                "error" { return $PSStyle.Formatting.Error }
                "warning" { return $PSStyle.Formatting.Warning }
                "ok" { return $PSStyle.Formatting.FormatAccent }
                default { return "" }
            }
        }
        "DevOps" {
            switch ($LogLevel) {
                "error" { return "##[error]" }
                "warning" { return "##[warning]" }
                default { "" }
            }
        }
        default {
            switch ($LogLevel) {
                "error" { return " [ERR] " }
                "warning" { return "[WRN]" }
                default { return " [INF] " }
            }
        }
    }
}

function Write-Header() {
    [CmdletBinding()]
    param(
        [string]$msg,
        [ValidateSet("error", "warning", "ok","normal")]
        [string] $LogLevel = "normal",
        [int]$Length = $script:Dashes,
        [ValidateSet("None","ANSI","DevOps")]
        [string] $ColorType = $script:ColorType,
        [string] $OutputFile = $script:OutputFile
    )
    $headerMessage = $LogLevel -eq "error" ? "ERROR" : ""
    $prefix = $LogLevel -eq "error" ? "" : $script:HeaderPrefix
    Write-Status -Msg $headerMessage -LogLevel $LogLevel -ColorType $ColorType -Char '-' -OutputFile $OutputFile
    Write-Status -Msg $msg -LogLevel normal -Length $Length -ColorType ANSI -Char ',' -OutputFile $OutputFile -Prefix $prefix -NoDate
}

function Write-Footer() {
    [CmdletBinding()]
    param(
        [string]$msg,
        [ValidateSet("error", "warning", "ok","normal")]
        [string] $LogLevel = "normal",
        [int]$Length = $script:Dashes,
        [ValidateSet("None","ANSI","DevOps")]
        [string] $ColorType = $script:ColorType,
        [string] $OutputFile = $script:OutputFile
    )
    $prefix = $LogLevel -eq "error" ? "" : $script:FooterPrefix
    Write-Status -Msg $msg -LogLevel normal -Length $Length -Suffix "`n" -ColorType ANSI -Char '`' -OutputFile $OutputFile -Prefix $prefix -NoDate
}

function Write-Status() {
    [CmdletBinding()]
    param(
        [string]$msg = "",
        [ValidateSet("error", "warning", "ok", "normal")]
        [string] $LogLevel = "normal",
        [int]$Length = $script:Dashes,
        [string] $Prefix = "",
        [string] $Suffix = "",
        [ValidateSet("None","ANSI","DevOps")]
        [string] $ColorType = $script:ColorType,
        [string] $Char = '-',
        [string] $OutputFile = $script:OutputFile,
        [switch] $NoDate
    )
    Set-StrictMode -Version Latest

    if ($NoDate) {
        $date = ""
    } else {
        $date = "$((Get-Date).ToString("u")) "
    }

    if ($VerbosePreference -ne 'Continue') {
        $Prefix += (MapColor $LogLevel $ColorType)
    }

    if ($Length -gt 0) {
        $maxWidth = $Host.UI.RawUI.WindowSize.Width
        $msgLen = ($Prefix + $date + $msg + $Suffix).Length
        if ($msgLen -lt $maxWidth) {
            $Length = [Math]::Min($Length, $maxWidth - $msgLen - 1)
            $msg = ($Char * $Length) + " $msg "
        }
    }

    if ($VerbosePreference -eq 'Continue') {
        "${Prefix}${date}${msg}${Suffix}" | Tee-Object $OutputFile -Append | Write-Verbose
    } else {
        "${Prefix}${date}${msg}${Suffix}" | Tee-Object $OutputFile -Append | Write-Host
    }
}
