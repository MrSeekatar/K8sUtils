# Import the script that defines the Deploy-MinimalJob -PassThru function
BeforeAll {
    Import-Module  $PSScriptRoot\..\K8sUtils\K8sUtils.psm1 -Force -ArgumentList $true
    Import-Module  $PSScriptRoot\Minimal.psm1 -Force -ArgumentList $true

    $env:invokeHelmAllowLowTimeouts = $true

    . $PSScriptRoot\TestHelpers.ps1
}

Describe "Deploys Minimal API" {

    It "runs init ok" {
        $deploy = Deploy-MinimalJob -PassThru

        Test-Job $deploy
    } -Tag 'Happy','j1'

    It "runs without init ok" {
        $deploy = Deploy-MinimalJob -PassThru -SkipInit

        Test-Job $deploy
    } -Tag 'Happy','j2'

    It "runs a dry run" {
        $deploy = Deploy-MinimalJob -PassThru -DryRun 2>&1 | Out-Null
        $deploy | Should -Be $null
    } -Tag 'Happy','j6'

    It "has main container crash" {
        $deploy = Deploy-MinimalJob -PassThru -SkipInit -SkipPreHook -Fail
        Test-Deploy $deploy -Running $false -RollbackStatus 'RolledBack'

        Test-MainPod $deploy.PodStatuses[0] -status 'Crash'
    } -Tag 'Crash','Sad','j7'

    It "has main container has bad image tag" {
        $deploy = Deploy-MinimalJob -PassThru -SkipInit -SkipPreHook -ImageTag zzz
        Test-Deploy $deploy -Running $false -RollbackStatus 'RolledBack'

        Test-MainPod $deploy.PodStatuses[0] -status 'ConfigError' -reason "ErrImageNeverPull"
    } -Tag 'Config','Sad','j8'

    It "has the main container with a bad secret name" {
        $deploy = Deploy-MinimalJob -PassThru -SkipInit -SkipPreHook -BadSecret
        Test-Deploy $deploy -Running $false -RollbackStatus 'RolledBack'

        Test-MainPod $deploy.PodStatuses[0] -status 'ConfigError' -reason "CreateContainerConfigError"
    } -Tag 'Config','Sad','j9'

    It "has the main container too short time out" {
        $deploy = Deploy-MinimalJob -PassThru -SkipInit -SkipPreHook -TimeoutSec 3 -RunCount 100
        Test-Deploy $deploy -Running $false -RollbackStatus 'RolledBack'

        Test-MainPod $deploy.PodStatuses[0] -status 'Timeout' -reason "Possible timeout"
    } -Tag 'Timeout','Sad','j10'

    It "has the main container time out" {
        $deploy = Deploy-MinimalJob -PassThru -SkipInit -SkipPreHook -TimeoutSec 10 -RunCount 100
        Test-Deploy $deploy -Running $false -RollbackStatus 'RolledBack'

        Test-MainPod $deploy.PodStatuses[0] -status 'Unknown' -reason "Possible timeout"
    } -Tag 'Timeout','Sad','j11'

    It "has a temporary startup timeout" {
        $deploy = Deploy-MinimalJob -PassThru -SkipInit -SkipPreHook -TimeoutSec 60 -RunCount 10 -StartupProbe
        Test-Deploy $deploy -Running $true

        Test-MainPod $deploy.PodStatuses[0]
    } -Tag 'Probe', 'Happy', 'j12'

    It "has a startup timeout" {
        $deploy = Deploy-MinimalJob -PassThru -SkipInit -SkipPreHook -TimeoutSec 10 -RunCount 10 -StartupProbe
        Test-Deploy $deploy -Running $false -RollbackStatus 'RolledBack'

        Test-MainPod $deploy.PodStatuses[0] -status 'Timeout' -reason "Possible timeout"
    } -Tag 'Sad', 'Timeout', 'Probe', 'j13'

    It "has an init failure" {
        $deploy = Deploy-MinimalJob -PassThru -SkipPreHook -InitFail
        Test-Deploy $deploy -Running $false -RollbackStatus 'RolledBack'

        Test-MainPod $deploy.PodStatuses[0] -status 'Crash' -reason "Possible timeout"
    } -Tag 'Sad', 'Crash', 'j16'

    It "has init bad config" {
        $deploy = Deploy-MinimalJob -PassThru -SkipPreHook -InitTag zzz
        Test-Deploy $deploy -Running $false -RollbackStatus 'RolledBack'

        Test-MainPod $deploy.PodStatuses[0] -status 'ConfigError' -reason "Possible timeout"
        $deploy.PodStatuses[0].LastBadEvents.Count | Should -BeGreaterThan 1
        $deploy.PodStatuses[0].LastBadEvents[1] | Should -Be 'Error: ErrImageNeverPull'

    } -Tag 'Sad', 'Crash', 'j17'

    It "has an init timeout" {
        $deploy = Deploy-MinimalJob -PassThru -SkipPreHook -TimeoutSec 5 -InitRunCount 50
        Test-Deploy $deploy -Running $false -RollbackStatus 'RolledBack'

        Test-MainPod $deploy.PodStatuses[0] -status 'Timeout' -reason "Possible timeout"
    } -Tag 'Sad', 'Timeout', 'j18'
}

