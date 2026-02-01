# called by Invoke-HelmUpgrade
function rollbackAndWarn {
    [CmdletBinding()]
    param ($SkipRollbackOnError, $releaseName, $msg, $prevVersion)

    try {
        Write-VerboseStatus "helm status --namespace $Namespace $ReleaseName -o json"
        $currentReleaseVersion = helm status --namespace $Namespace $ReleaseName -o json | ConvertFrom-Json -Depth 20 -AsHashtable # AsHashTable allows for duplicate keys in env, etc.
        if (!$currentReleaseVersion -or !($currentReleaseVersion.ContainsKey('version'))) {
            Write-Status "Unexpected response from helm status, not rolling back" -LogLevel warning
            Write-Status "Current helm release: $($currentReleaseVersion | ConvertTo-Json -Depth 20 -EnumsAsStrings)"
            return [RollbackStatus]::HelmStatusFailed
        }
        Write-VerboseStatus "Current version of '$ReleaseName' is $($currentReleaseVersion.version)"
        if (!$currentReleaseVersion -or $currentReleaseVersion.version -eq $prevVersion) {
            Write-Status "No change in release '$ReleaseName', not rolling back $($currentReleaseVersion.version) = $prevVersion" -LogLevel warning
            # throw "$msg, no change"
            Write-Warning "$msg, no change"
            return [RollbackStatus]::NoChange
        }

        if (!$SkipRollbackOnError) {
            Write-Header "Rolling back release '$ReleaseName' from $($currentReleaseVersion.version) back to $prevVersion due to errors" -LogLevel Error
            $errFile = Get-TempLogFile
            helm rollback $ReleaseName --wait 2>&1 | Tee-Object $errFile | Write-MyHost
            $exit = $LASTEXITCODE
            $content = Get-Content $errFile -Raw
            if ($exit -ne 0 -and ($content -like '*Error: release has no 0 version*' -or $content -like '*Error: release: not found*')) {
                Write-VerboseStatus "Last exit code on rollback was $exit."
                Write-Status "Helm rollback failed, trying uninstall" -LogLevel Error
                helm uninstall $ReleaseName 2>&1 | Write-MyHost
            }
            Remove-Item $errFile -ErrorAction SilentlyContinue
            Write-Footer "End rolling back release '$ReleaseName' due to errors"
            # throw "$msg, rolled back"
            Write-Warning "$msg, rolled back"
            return [RollbackStatus]::RolledBack
        } else {
            # throw "$msg, but not rolling back since -SkipRollbackOnError was specified"
            Write-Warning "$msg, but not rolling back since -SkipRollbackOnError was specified"
            return [RollbackStatus]::Skipped
        }
        return [RollbackStatus]::DeployedOk
    } catch {
        Write-Warning "Caught error rolling back in catch"
        Write-Warning "$_`n$($_.ScriptStackTrace)"
        return [RollbackStatus]::HelmStatusFailed
    }
}