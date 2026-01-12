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

    Write-Host "=== Testing Start-ThreadJob Parameter Passing ===" -ForegroundColor Cyan

    # Test 1: Using InputObject
    Write-Host "`n[Test 1] InputObject Method" -ForegroundColor Yellow
    $inputJob =  Start-ThreadJob -ScriptBlock {
        param($config)
        $VerbosePreference = $using:VerbosePreference
        Write-Verbose "Thread job executing: InputObject method with config"
        Write-Host "input type is $($input.GetType().Name)"
        # Write-Host "$($input | Get-Member)"
        Write-Host "input is $($input | Out-String)"
        foreach ($item in $input) {
            Write-Host "Config Key: $($item.Key), Value: $($item.Value)"
        }
        $ii = $input | Select-Object -First 1
        if ($ii) {
            Write-Host "ii type is $($ii.GetType().Name)"
            Write-Host "$($ii | Get-Member)"
            Write-Host "ii is $($ii | Out-String)"
        }
    } -InputObject $configHash

    $inputJob | Receive-Job -Wait -AutoRemoveJob

    # Test 2: Using ArgumentList
    Write-Host "`n[Test 2] ArgumentList Method" -ForegroundColor Yellow
    $argJob = Start-ThreadJob -ScriptBlock {
        param($intValue, $config, $timestamp)
        $VerbosePreference = $using:VerbosePreference
        Write-Verbose "Thread job executing: ArgumentList method with integer: $intValue"
    } -ArgumentList $i, $configHash, (Get-Date)

    $argJob | Receive-Job -Wait -AutoRemoveJob

    # Test 3: Using $using: scope modifier
    Write-Host "`n[Test 3] `$using: Scope Modifier Method" -ForegroundColor Yellow
    $usingJob = Start-ThreadJob -ScriptBlock {
        $VerbosePreference = $using:VerbosePreference
        Write-Verbose "Thread job executing: Using scope modifier with i=$using:i"
    }

    $usingJob | Receive-Job -Wait -AutoRemoveJob

    # Test 4: Combining multiple methods
    Write-Host "`n[Test 4] Combined Methods" -ForegroundColor Yellow
    $configHashVar = Get-Variable -Name configHash
    $combinedJob = $configHash | Start-ThreadJob -ScriptBlock {
        param($inputConfig, $argInt)
        $VerbosePreference = $using:VerbosePreference
        Write-Verbose "Thread job executing: Combined methods with integer=$argInt and using i=$using:i"
        $configHash = ($using:configHashVar).Value
        Write-Host "Config from InputObject:"
        $configHash.Timeout = 100
    } -ArgumentList $i

    $combinedJob | Receive-Job -Wait -AutoRemoveJob
    Write-Host "After job completion, original configHash Timeout: $($configHash.Timeout)" -ForegroundColor Green
