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
    } -Tag 'Happy','new'

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
    } -Tag 'Happy',"Shortest"

    It "runs with prehook only ok" {
        $deploy = Deploy-Minimal -PassThru  -SkipInit -SkipDeploy

        $deploy.Running | Should -Be $false
        $deploy.ReleaseName | Should -Be 'test'
        $deploy.PodStatuses | Should -Be $null
        $deploy.PreHookStatus.Status | Should -Be 'Running'
        $deploy.RollbackStatus | Should -Be 'DeployedOk'
    } -Tag 'Happy'

    It "runs a dry run" {
        $deploy = Deploy-Minimal -PassThru -DryRun 2>&1 | Out-Null
        $deploy | Should -Be $null
    } -Tag 'Happy'

    It "has main container crash" {
        $deploy = Deploy-Minimal -PassThru -SkipInit -SkipPreHook -Fail
        Test-Deploy $deploy -Running $false -RollbackStatus 'RolledBack'

        Test-MainPod $deploy.PodStatuses[0] -status 'Crash'
    } -Tag 'Crash','Sad'

    It "has main container has bad image tag" {
        $deploy = Deploy-Minimal -PassThru -SkipInit -SkipPreHook -ImageTag zzz
        Test-Deploy $deploy -Running $false -RollbackStatus 'RolledBack'

        Test-MainPod $deploy.PodStatuses[0] -status 'ConfigError' -reason "ErrImageNeverPull"
    } -Tag 'Config','Sad'

    It "has the main container with a bad secret name" {
        $deploy = Deploy-Minimal -PassThru -SkipInit -SkipPreHook -BadSecret
        Test-Deploy $deploy -Running $false -RollbackStatus 'RolledBack'

        Test-MainPod $deploy.PodStatuses[0] -status 'ConfigError' -reason "CreateContainerConfigError"
    } -Tag 'Config','Sad'

    It "has the main container too short time out" {
        $deploy = Deploy-Minimal -PassThru -SkipInit -SkipPreHook -TimeoutSec 3 -RunCount 100
        Test-Deploy $deploy -Running $false -RollbackStatus 'RolledBack'

        Test-MainPod $deploy.PodStatuses[0] -status 'Timeout' -reason "Possible timeout"
    } -Tag 'Timeout','Sad'

    It "has the main container time out" {
        $deploy = Deploy-Minimal -PassThru -SkipInit -SkipPreHook -TimeoutSec 10 -RunCount 100
        Test-Deploy $deploy -Running $false -RollbackStatus 'RolledBack'

        Test-MainPod $deploy.PodStatuses[0] -status 'Unknown' -reason "Possible timeout"
    } -Tag 'Timeout','Sad'

    It "has a temporary startup timeout" {
        $deploy = Deploy-Minimal -PassThru -SkipInit -SkipPreHook -TimeoutSec 60 -RunCount 10 -StartupProbe
        Test-Deploy $deploy -Running $true

        Test-MainPod $deploy.PodStatuses[0]
    } -Tag 'Probe', 'Happy'

    It "has a startup timeout" {
        $deploy = Deploy-Minimal -PassThru -SkipInit -SkipPreHook -TimeoutSec 10 -RunCount 10 -StartupProbe
        Test-Deploy $deploy -Running $false -RollbackStatus 'RolledBack'

        Test-MainPod $deploy.PodStatuses[0] -status 'Timeout' -reason "Possible timeout"
    } -Tag 'Sad', 'Timeout', 'Probe'

    It "has a bad probe" {
        $deploy = Deploy-Minimal -PassThru -SkipInit -SkipPreHook -TimeoutSec 120 -Readiness '/fail'
        Test-Deploy $deploy -Running $false -RollbackStatus 'RolledBack'

        Test-MainPod $deploy.PodStatuses[0] -status 'Unknown' -reason "Possible timeout"
        $deploy.PodStatuses[0].LastBadEvents.Count | Should -Be 1
        $deploy.PodStatuses[0].LastBadEvents[0] | Should -BeLike 'Readiness probe failed:*'
    } -Tag 'Sad','Probe'

    It "has a prehook job top timeout" {
        $deploy = Deploy-Minimal -PassThru -SkipInit -HookRunCount 50 -TimeoutSec 10
        Test-Deploy $deploy -Running $false -podCount 0 -RollbackStatus 'RolledBack'

        # no pod statuses
    } -Tag 'Sad', 'Timeout'

    It "has an init failure" {
        $deploy = Deploy-Minimal -PassThru -SkipPreHook -InitFail
        Test-Deploy $deploy -Running $false -RollbackStatus 'RolledBack'

        Test-MainPod $deploy.PodStatuses[0] -status 'Crash' -reason "Possible timeout"
    } -Tag 'Sad', 'Crash'

    It "has init bad config" {
        $deploy = Deploy-Minimal -PassThru -SkipPreHook -InitTag zzz
        Test-Deploy $deploy -Running $false -RollbackStatus 'RolledBack'

        Test-MainPod $deploy.PodStatuses[0] -status 'ConfigError' -reason "Possible timeout"
        $deploy.PodStatuses[0].LastBadEvents.Count | Should -BeGreaterThan 1
        $deploy.PodStatuses[0].LastBadEvents[1] | Should -Be 'Error: ErrImageNeverPull'

    } -Tag 'Sad', 'Crash'

    It "has an init timeout" {
        $deploy = Deploy-Minimal -PassThru -SkipPreHook -TimeoutSec 5 -InitRunCount 50
        Test-Deploy $deploy -Running $false -RollbackStatus 'RolledBack'

        Test-MainPod $deploy.PodStatuses[0] -status 'Timeout' -reason "Possible timeout"
    } -Tag 'Sad', 'Timeout'

    It "has prehook job hook timeout" {
        $deploy = Deploy-Minimal -PassThru -SkipInit -HookRunCount 100 -PreHookTimeoutSecs 5 -Verbose
        $global:deploy = $deploy
        $deploy.Running | Should -Be $false
        $deploy.RollbackStatus | Should -Be 'RolledBack'
        $deploy.ReleaseName | Should -Be 'test'

        Test-PreHook $deploy.PreHookStatus -status 'Timeout' -containerStatus 'Running'
    } -Tag 'Timeout','Negative'

    It "has prehook job crash" {
        $deploy = Deploy-Minimal -PassThru -HookFail -TimeoutSecs 20 -PreHookTimeoutSecs 20
        Test-Deploy $deploy -Running $false -PodCount 0 -RollbackStatus 'RolledBack'

        $deploy.PreHookStatus.Status | Should -Be 'Crash'
    } -Tag 'Crash','Sad'

    It "has prehook config error" {
        $deploy = Deploy-Minimal -PassThru -HookTag zzz
        Test-Deploy $deploy -Running $false -PodCount 0 -RollbackStatus 'RolledBack'

        $deploy.PreHookStatus.Status | Should -Be 'ConfigError'
        $deploy.PreHookStatus.LastBadEvents.Count | Should -BeGreaterThan 1
        $deploy.PreHookStatus.LastBadEvents[1] | Should -Be 'Error: ErrImageNeverPull'
    } -Tag 'Config','Sad'

    It "has prehook timeout" {
        $deploy = Deploy-Minimal -PassThru -PreHookTimeoutSecs 5 -HookRunCount 100
        Test-Deploy $deploy -Running $false -PodCount 0 -RollbackStatus 'RolledBack'

        $deploy.PreHookStatus.Status | Should -Be 'Timeout'
    } -Tag 'Config','Sad'

    It "tests error if checking preHook, but not making one" {
        try {
            Deploy-Minimal -AlwaysCheckPreHook
        } catch {
            $_.Exception.Message | Should -BeLike "Error! When looking for preHook, nothing returned from kubectl get rs -l app.kubernetes.io/instance=test,app.kubernetes.io/name=minimal --namespace default*"
        }
    } -Tag 'Sad'
}

