$script:ColorType = "ANSI"
$script:HeaderPrefix = ""
$script:FooterPrefix = ""
$script:AddDate = $true
$script:Dashes = 30
$script:InHeader = 0

function Get-TempLogFile($prefix = "k8s-") {
    $temp = [System.IO.Path]::GetTempFileName()
    $ret = Join-Path( Split-Path -Path $temp -Parent) "$prefix$(Split-Path -Path $temp -Leaf)"
    $script:OutputFile = $ret
    return $ret
}

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
    if ($script:InHeader -gt 0) {
        Write-Status "Nesting Write-Header ($script:InHeader) with message '$msg'" -LogLevel "warning"
    }
    $script:InHeader += 1
    $headerMessage = $LogLevel -eq "error" ? "ERROR" : ""
    $prefix = $LogLevel -eq "error" ? "" : $HeaderPrefix
    Write-Status -Msg $headerMessage -LogLevel $LogLevel -ColorType $ColorType -Char '╒═╕' -Length 80
    Write-Status -Msg $msg -LogLevel $LogLevel -Length $Length -ColorType $ColorType -Char '─' -Prefix $prefix

    $script:headerLogLevel = $LogLevel
    $script:headerLength = $Length
    $script:headerColorType = $ColorType
}

function Write-Footer() {
    [CmdletBinding()]
    param(
        [string] $msg,
        [string] $FooterPrefix = $script:FooterPrefix
    )
    $prefix = $script:headerLogLevel -eq "error" ? "" : $FooterPrefix
    Write-Status -Msg $msg -LogLevel $headerLogLevel -Length $script:headerLength -ColorType $script:headerColorType -Char '─' -Prefix $prefix
    Write-Status -LogLevel $script:headerLogLevel -ColorType $script:headerColorType -Char '╘═╛' -Length 80

    if ($script:InHeader -eq 0) {
        Write-Warning "Write-Footer called without a Write-Header"
        $callStack = Get-PSCallStack
        if ($callStack) {
            $stack = ""
            foreach ($frame in $callStack | Where-Object { $_.ScriptName -like '*K8sUtils*' }) {
                $stack += "$($frame.FunctionName) at $($frame.ScriptName):$($frame.ScriptLineNumber)`n"
            }
            Write-Status -Msg "Call Stack:`n$stack" -LogLevel warning
        }
    }
    $script:InHeader -= 1
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
