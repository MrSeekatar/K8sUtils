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
    $moduleName = Join-Path $PSScriptRoot '..\K8sUtils\K8sUtils.psd1'
    $configHashVar = Get-Variable -Name configHash
    $parms = @("info","-o","text")

    $usingJob = Start-ThreadJob -ScriptBlock {
        $VerbosePreference = $using:VerbosePreference
        Write-Verbose "Thread job executing: Combined methods with integer=$argInt and using i=$using:i"

        Import-Module $using:moduleName -ArgumentList $true -Verbose:$false
        Write-Verbose "In thread. Loaded K8sUtil version $((Get-Module K8sUtils).Version). LogFileFolder is '$LogFileFolder'"

        $configHash = ($using:configHashVar).Value
        Write-Host "Config from InputObject: $($inputConfig | Out-String)"
        $configHash.Timeout = 300
        rdctl @using:parms
        Write-Verbose "Thread job executing: Using scope modifier with i=$using:i"
    }

    $usingJob | Receive-Job -Wait -AutoRemoveJob
    Write-Host "After job completion, original configHash Timeout: $($configHash.Timeout)" -ForegroundColor Green

    # Test 4: Combining multiple methods
    Write-Host "`n[Test 4] Combined Methods" -ForegroundColor Yellow

    $combinedJob = $configHash | Start-ThreadJob -ScriptBlock {
        param($inputConfig, $argInt)
        $VerbosePreference = $using:VerbosePreference
        Write-Verbose "Thread job executing: Combined methods with integer=$argInt and using i=$using:i"

        Import-Module $using:moduleName -ArgumentList $true -Verbose:$false
        Write-Verbose "In thread. Loaded K8sUtil version $((Get-Module K8sUtils).Version). LogFileFolder is '$LogFileFolder'"

        $configHash = ($using:configHashVar).Value
        Write-Host "Config from InputObject: $($inputConfig | Out-String)"
        $configHash.Timeout = 400
    } -ArgumentList $i

    $combinedJob | Receive-Job -Wait -AutoRemoveJob
    Write-Host "After job completion, original configHash Timeout: $($configHash.Timeout)" -ForegroundColor Green
