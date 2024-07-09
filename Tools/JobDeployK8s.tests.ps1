# Import the script that defines the Deploy-MinimalJobK8s function
BeforeAll {
    Import-Module  $PSScriptRoot\..\K8sUtils\K8sUtils.psm1 -Force -ArgumentList $true
    Import-Module  $PSScriptRoot\Minimal.psm1 -Force -ArgumentList $true

    $env:invokeHelmAllowLowTimeouts = $true

    . $PSScriptRoot\TestHelpers.ps1
}

Describe "Deploys Minimal API" {

    It "runs init ok" {
        $deploy = Deploy-MinimalJobK8s

        Test-Pod $deploy -nameLike 'test-job-*' -containerName 'test-job' -status 'Completed' -containerStatus 'Completed'
    } -Tag 'Happy','k1'

    It "runs without init ok" {
        $deploy = Deploy-MinimalJobK8s -SkipInit

        Test-Pod $deploy -nameLike 'test-job-*' -containerName 'test-job' -status 'Completed' -containerStatus 'Completed'
    } -Tag 'Happy','k2'

    It "runs a dry run" {
        $deploy = Deploy-MinimalJobK8s -DryRun 2>&1 | Out-Null
        $deploy | Should -Be $null
    } -Tag 'Happy','k6'

    It "has main container crash" {
        $deploy = Deploy-MinimalJobK8s -SkipInit -Fail
        Test-Job $deploy -Running $false -status 'Crash'
    } -Tag 'Crash','Sad','k7'

    It "has main container has bad image tag" {
        $deploy = Deploy-MinimalJobK8s -SkipInit -ImageTag zzz
        Test-Job $deploy -Running $false -status 'ConfigError' -reason "ErrImageNeverPull"
    } -Tag 'Config','Sad','k8'

    It "has the main container with a bad secret name" {
        $deploy = Deploy-MinimalJobK8s -SkipInit -BadSecret
        Test-Job $deploy -Running $false -status 'ConfigError' -reason "CreateContainerConfigError"
    } -Tag 'Config','Sad','k9'

    It "has the main container too short time out" {
        $deploy = Deploy-MinimalJobK8s -SkipInit -TimeoutSec 3 -RunCount 100
        Test-Job $deploy -Running $false -status 'Timeout' -reason "Possible timeout"
    } -Tag 'Timeout','Sad','k10'

    It "has the main container time out" {
        $deploy = Deploy-MinimalJobK8s -SkipInit -TimeoutSec 10 -RunCount 100
        Test-Job $deploy -Running $false -status 'Timeout' -reason "Possible timeout"
    } -Tag 'Timeout','Sad','k11'

    It "has an init failure" {
        $deploy = Deploy-MinimalJobK8s -InitFail
        Test-Job $deploy -Running $false -status 'Crash' -reason "Possible timeout"
    } -Tag 'Sad', 'Crash', 'k16'

    It "has init bad config" {
        $deploy = Deploy-MinimalJobK8s -InitTag zzz
        Test-Job $deploy -Running $false -status 'ConfigError' -reason "Possible timeout"
    } -Tag 'Sad', 'Crash', 'k17'

    It "has an init timeout" {
        $deploy = Deploy-MinimalJobK8s -TimeoutSec 5 -InitRunCount 50
        Test-Job $deploy -Running $false -status 'Timeout' -reason "Possible timeout"
    } -Tag 'Sad', 'Timeout', 'k18'
}

