<#
.SYNOPSIS
Tests Start-ThreadJob with InputObject, ArgumentList, and $using: variable passing.

.DESCRIPTION
Demonstrates different methods to pass parameters to thread jobs including
InputObject, ArgumentList, and $using: scope modifier for complex objects.

.EXAMPLE
Test-ThreadJobParameters -Verbose
#>


    [CmdletBinding()]
    param()

    # Test data - complex objects
    $configHash = @{
        Environment = "Production"
        Timeout = 30
        RetryCount = 3
        Servers = @("server1", "server2", "server3")
    }
    $i = 42

    Write-Host "`n[Test 4] Combined Methods" -ForegroundColor Cyan
    $combinedJob = configHaStart-ThreadJob -ScriptBlock {
        param($inputConfig, $argInt)
        $VerbosePreference = $using:VerbosePreference
        Write-Verbose "Thread job executing: Combined methods with integer=$argInt and using i=$using:i"
        Write-Verbose "Config Timeout is: $($inputConfig.TimeOut)"
        $inputConfig.Timeout = 100
        Write-Host "Input object is $($input.GetType().Name)" -ForegroundColor Green
        Write-Host "InputConfig object is $($inputConfig.GetType().Name)" -ForegroundColor Green
        Write-Verbose ($input | Out-String)
        Write-Verbose "Now Config Timeout is: $($inputConfig.TimeOut)"
    } -ArgumentList $configHash,$i -InputObject $configHash

    Write-Host "Hash is $($configHash.GetType().Name)" -ForegroundColor Green

    Write-Host "`n[Test 4] Receiving" -ForegroundColor Cyan
    $combinedJob | Receive-Job -Wait -AutoRemoveJob
    Write-Host "i is $i" -ForegroundColor Cyan
    Write-Host $configHash -ForegroundColor Cyan
