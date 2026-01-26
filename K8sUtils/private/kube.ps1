<#
.SYNOPSIS
Wrapper around kubectl to catch stderr

.PARAMETER LogIt
Set to log the kubectl command being run as information.

.PARAMETER argList
Remaining arguments are passed as parameters to kubectl

.NOTES
Check $LASTEXITCODE for success/failure
#>
function kube
{
    $argList = $args
    $tempFile = [System.IO.Path]::GetTempFileName()
    if ($args -contains "-LogIt") {
        Write-Status "kubectl $argList" -LogLevel normal
        $argList = $args | Where-Object {$_ -ne "-LogIt"}
    } else {
        Write-VerboseStatus "kubectl $argList"
    }
    kubectl $argList 2> $tempFile
    if ($LASTEXITCODE -ne 0) {
        try {
            Write-Warning "'kubectl $argList' exited with $LASTEXITCODE."
            Get-Content $tempFile | ForEach-Object { Write-Warning $_ }
        } catch {}
    }
    Remove-Item $tempFile -ErrorAction SilentlyContinue
}