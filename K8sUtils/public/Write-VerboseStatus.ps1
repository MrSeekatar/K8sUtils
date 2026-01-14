$script:frames = ""
$script:verboseStack = $false

# write verbose-like status with call stack
function Write-VerboseStatus([string] $msg) {
    if ($VerbosePreference -ne 'Continue') {
        return
    }
    $frames = ""
    if ($script:verboseStack)
    {
        $stack = Get-PSCallStack
        $frameList = @()
        $frames = $stack | Select-Object -Skip 1 -SkipLast 1
        foreach ($frame in $frames) {
            $location = $frame.Location -match "line (\d+)" ? $Matches[1] : ""
            if ($frame.Command -eq 'Invoke-HelmUpgrade') {
                $frameList += "$($frame.Command)#L$Location"
                break
            }
            $frameList += "$($frame.Command)#L$Location"
        }
        $frames = "$($frameList -join " <- ")`n  => "
        if ($frameList -and $frames -ne $script:frames ) {
            $script:frames = $frames
        } else {
            $frames = ""
        }
    }
    Write-Host "$($PSStyle.Formatting.Verbose)VRB: $frames$msg$($PSStyle.Reset)"
}
