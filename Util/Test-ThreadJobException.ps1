param ($test)
if ($test -eq 1 ) {
    $ErrorActionPreference = 'Continue'
    $job = Start-ThreadJob -ScriptBlock {
        Write-Host "2 In ThreadJob$using:test started, about to throw exception..." -ForegroundColor Yellow
        throw "2.1 This is a test exception from ThreadJob$using:test"
    }

    try {
        Write-Host "1 About to receive job$test results..." -ForegroundColor Cyan
        $job | Receive-Job -Wait -AutoRemoveJob
        Write-Host "3 Finished receiving job$test results." -ForegroundColor Cyan
    } catch {
        Write-Host "3 Caught exception from ThreadJob${test}:" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
    }
} elseif ($test -eq 2) {

    # set $ErrorActionPreference to 'Stop' inside the job, and 'Continue' outside
    $ErrorActionPreference = 'Continue'
    $job = Start-ThreadJob -ScriptBlock {
        $ErrorActionPreference = 'Stop'
        Write-Host "2 In ThreadJob$using:test started, about to throw exception..." -ForegroundColor Yellow
        throw "2.1 This is a test exception from ThreadJob$using:test"
    }

    $ErrorActionPreference = 'Stop'
    try {
        Write-Host "1 About to receive job$test results..." -ForegroundColor Cyan
        $job | Receive-Job -Wait -AutoRemoveJob
        Write-Host "3 Finished receiving job$test results." -ForegroundColor Cyan
    } catch {
        Write-Host "3 Caught exception from ThreadJob${test}:" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
    }
} elseif ($test -eq 3) {

    # set $ErrorActionPreference to 'Stop' inside the job, and 'Stop' outside
    $job = Start-ThreadJob -ScriptBlock {
        $ErrorActionPreference = 'Stop'
        Write-Host "2 In ThreadJob$using:test started, about to throw exception..." -ForegroundColor Yellow
        throw "2.1 This is a test exception from ThreadJob$using:test"
    }

    $ErrorActionPreference = 'Stop'
    try {
        $ErrorActionPreference = 'Continue'
        Write-Host "1 About to receive job$test results..." -ForegroundColor Cyan
        $job | Receive-Job -Wait -AutoRemoveJob
        Write-Host "3 Finished receiving job$test results." -ForegroundColor Cyan # never get here
        $ErrorActionPreference = 'Stop'
    } catch {
        Write-Host "3 Caught exception from ThreadJob${test}:" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
    }

} elseif ($test -eq 4) {

    # set $ErrorActionPreference to 'Stop' inside the job, and 'Stop' outside
    $ErrorActionPreference = 'Stop'
    $job = Start-ThreadJob -ScriptBlock {
        # kubectl write to stderr never has prefix
        # if stop and we call Write-Error, it has this prefix to text:
        # The running command stopped because the preference variable "ErrorActionPreference" or common parameter is set to Stop:
        $ErrorActionPreference = 'Continue'
        Write-Host "2 In ThreadJob$using:test started, about to write to std error $errorActionPreference" -ForegroundColor Yellow
        # kubectl get pod non-existent-pod # writes to stderr
        Write-Error "2.1 This is a test error output from ThreadJob$using:test" # text of Exception message
        Write-Host "Don't get here"
        Write-Error "2.2 This does not show up"
        $LASTEXITCODE = 0
        Write-Host "2.1 In ThreadJob$using:test after write to std error" -ForegroundColor Yellow
    } -ErrorAction Stop

    try {
        Write-Host "1 About to receive job$test results..." -ForegroundColor Cyan
        $job | Receive-Job -Wait -AutoRemoveJob
        Write-Host "3 Finished receiving job$test results." -ForegroundColor Cyan # never get here since stderr throws
    } catch {
        Write-Host "3 Caught exception from ThreadJob${test}:" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
    }

}