# Import the script that defines the Deploy-Minimal -PassThru function
BeforeAll {
    Import-Module  $PSScriptRoot\..\K8sUtils\K8sUtils.psm1 -Force -ArgumentList $true
    Import-Module  $PSScriptRoot\Minimal.psm1 -Force -ArgumentList $true

    $env:invokeHelmAllowLowTimeouts = $true

    . $PSScriptRoot\TestHelpers.ps1
}

Describe "Deploys Minimal API" {

    It "runs hook, init ok" {
        $deploy = Deploy-Minimal -PassThru

        Test-Deploy $deploy

        Test-PreHook $deploy.PreHookStatus

        Test-MainPod $deploy.PodStatuses[0]
    } -Tag 'Happy'

    It "runs without init ok" {
        $deploy = Deploy-Minimal -PassThru -SkipInit

        Test-Deploy $deploy

        Test-PreHook $deploy.PreHookStatus

        Test-MainPod $deploy.PodStatuses[0]
    } -Tag 'Happy'

    It "runs without prehook ok" {
        $deploy = Deploy-Minimal -PassThru -SkipPreHook

        Test-Deploy $deploy

        Test-MainPod $deploy.PodStatuses[0]
    } -Tag 'Happy'

    It "runs without init or prehook ok" {
        $deploy = Deploy-Minimal -PassThru -SkipPreHook -SkipInit

        Test-Deploy $deploy

        Test-MainPod $deploy.PodStatuses[0]
    } -Tag 'Happy'

    It "runs a dry run" {
        $deploy = Deploy-Minimal -PassThru -DryRun 2>&1 | Out-Null
        $deploy | Should -Be $null
    } -Tag 'Happy'

    It "has main container crash" {
        $deploy = Deploy-Minimal -PassThru -SkipInit -SkipPreHook -Fail
        Test-Deploy $deploy -Running $false

        Test-MainPod $deploy.PodStatuses[0] -status 'Crash'
    } -Tag 'Crash','Negative'

    It "has main container has bad image tag" {
        $deploy = Deploy-Minimal -PassThru -SkipInit -SkipPreHook -ImageTag zzz
        Test-Deploy $deploy -Running $false

        Test-MainPod $deploy.PodStatuses[0] -status 'ConfigError' -reason "ErrImageNeverPull"
    } -Tag 'Config','Negative'

    It "has the main container with a bad secret name" {
        $deploy = Deploy-Minimal -PassThru -SkipInit -SkipPreHook -BadSecret
        Test-Deploy $deploy -Running $false

        Test-MainPod $deploy.PodStatuses[0] -status 'ConfigError' -reason "CreateContainerConfigError"
    } -Tag 'Config','Negative'

    It "has the main container time out" {
        $deploy = Deploy-Minimal -PassThru -SkipInit -SkipPreHook -RunCount 100
        Test-Deploy $deploy -Running $false

        Test-MainPod $deploy.PodStatuses[0] -status 'Unknown' -reason "Possible timeout"
    } -Tag 'Timeout','Negative'

    It "has a temporary startup timeout" {
        $deploy = Deploy-Minimal -PassThru -SkipInit -SkipPreHook -TimeoutSec 60 -RunCount 10 -StartupProbe
        Test-Deploy $deploy -Running $true

        Test-MainPod $deploy.PodStatuses[0]
    } -Tag 'Probe', 'Happy'

    It "has a temporary startup timeout" {
        $deploy = Deploy-Minimal -PassThru -SkipInit -SkipPreHook -TimeoutSec 10 -RunCount 10 -StartupProbe
        Test-Deploy $deploy -Running $false

        Test-MainPod $deploy.PodStatuses[0] -status 'Unknown' -reason "Possible timeout"
    } -Tag 'Negative', 'Timeout', 'Probe'

    It "has a bad probe" {
        $deploy = Deploy-Minimal -PassThru -SkipInit -SkipPreHook -TimeoutSec 120 -Readiness '/fail'
        Test-Deploy $deploy -Running $false

        Test-MainPod $deploy.PodStatuses[0] -status 'Unknown' -reason "Possible timeout"
        $deploy.PodStatuses[0].LastBadEvents.Count | Should -Be 1
        $deploy.PodStatuses[0].LastBadEvents[0] | Should -BeLike 'Readiness probe failed:*'
    } -Tag 'Negative','Probe'

    It "has a prehook job top timeout" {
        $deploy = Deploy-Minimal -PassThru -SkipInit -HookRunCount 50 -TimeoutSec 10
        Test-Deploy $deploy -Running $false -podCount 0

        # no pod statuses
    } -Tag 'Negative', 'Timeout'

    It "has an init timeout" {
        $deploy = Deploy-Minimal -PassThru -SkipPreHook -TimeoutSec 10 -InitRunCount 50
        Test-Deploy $deploy -Running $false

        Test-MainPod $deploy.PodStatuses[0] -status 'Unknown' -reason "Possible timeout"
    } -Tag 'Negative', 'Timeout'

    It "has the prehook job hook times" {
        $deploy = Deploy-Minimal -PassThru -SkipInit -HookRunCount 100 -PreHookTimeoutSecs 5
        $deploy.Running | Should -Be $false
        $deploy.ReleaseName | Should -Be 'test'

        Test-PreHook $deploy.PreHookStatus # will be running
    } -Tag 'Timeout','Negative'

    It "has prehook job crash" {
        $deploy = Deploy-Minimal -PassThru -HookFail -TimeoutSecs 20 -PreHookTimeoutSecs 20
        Test-Deploy $deploy -Running $false -PodCount 0
        $deploy.PreHookStatus.Status | Should -Be 'Crash'
    } -Tag 'Crash','Negative','New'
}

