# Import the script that defines the Deploy-Minimal -PassThru function
BeforeAll {
    Import-Module  $PSScriptRoot\Minimal.psm1 -Force -ArgumentList $true
    Import-Module  $PSScriptRoot\..\K8sUtils\K8sUtils.psm1 -Force -ArgumentList $true

    $env:invokeHelmAllowLowTimeouts = $true

    . $PSScriptRoot\TestHelpers.ps1
}

Describe "Deploys Minimal API" {

    It "runs hook, init ok" {
        $deploy = Deploy-Minimal -PassThru

        Test-Deploy $deploy

        Test-PreHook $deploy.PreHookStatus

        Test-MainPod $deploy.PodStatuses[0]
    } -Tag 'Happy','t1'

    It "runs without init ok" {
        $deploy = Deploy-Minimal -PassThru -SkipInit

        Test-Deploy $deploy

        Test-PreHook $deploy.PreHookStatus

        Test-MainPod $deploy.PodStatuses[0]
    } -Tag 'Happy','t2'

    It "runs without prehook ok" {
        $deploy = Deploy-Minimal -PassThru -SkipPreHook

        Test-Deploy $deploy

        Test-MainPod $deploy.PodStatuses[0]
    } -Tag 'Happy','t3'

    It "runs without init or prehook ok" {
        $deploy = Deploy-Minimal -PassThru -SkipPreHook -SkipInit

        Test-Deploy $deploy

        Test-MainPod $deploy.PodStatuses[0]
    } -Tag 'Happy',"Shortest",'t4'

    It "runs with prehook only ok" {
        $deploy = Deploy-Minimal -PassThru  -SkipInit -SkipDeploy

        $deploy.Running | Should -Be $false
        $deploy.ReleaseName | Should -Be 'test'
        $deploy.PodStatuses | Should -Be $null
        $deploy.PreHookStatus.Status | Should -Be 'Completed'
        $deploy.RollbackStatus | Should -Be 'DeployedOk'
    } -Tag 'Happy','t5'

    It "runs a dry run" {
        $deploy = Deploy-Minimal -PassThru -DryRun 2>&1 | Out-Null
        $deploy | Should -Be $null
    } -Tag 'Happy','t6'

    It "has main container crash" {
        $deploy = Deploy-Minimal -PassThru -SkipInit -SkipPreHook -Fail
        Test-Deploy $deploy -Running $false -RollbackStatus 'RolledBack'

        Test-MainPod $deploy.PodStatuses[0] -status 'Crash'
    } -Tag 'Crash','Sad','t7'

    It "has main container has bad image tag" {
        $deploy = Deploy-Minimal -PassThru -SkipInit -SkipPreHook -ImageTag zzz
        Test-Deploy $deploy -Running $false -RollbackStatus 'RolledBack'

        Test-MainPod $deploy.PodStatuses[0] -status 'ConfigError' -reason "ErrImageNeverPull"
    } -Tag 'Config','Sad','t8'

    It "has the main container with a bad secret name" {
        $deploy = Deploy-Minimal -PassThru -SkipInit -SkipPreHook -BadSecret
        Test-Deploy $deploy -Running $false -RollbackStatus 'RolledBack'

        Test-MainPod $deploy.PodStatuses[0] -status 'ConfigError' -reason "CreateContainerConfigError"
    } -Tag 'Config','Sad','t9'

    It "has the main container too short time out" {
        $deploy = Deploy-Minimal -PassThru -SkipInit -SkipPreHook -TimeoutSec 3 -RunCount 100
        Test-Deploy $deploy -Running $false -RollbackStatus 'RolledBack'

        Test-MainPod $deploy.PodStatuses[0] -status 'Timeout' -reason "Possible timeout"
    } -Tag 'Timeout','Sad','t10'

    It "has the main container time out" {
        $deploy = Deploy-Minimal -PassThru -SkipInit -SkipPreHook -TimeoutSec 10 -RunCount 100
        Test-Deploy $deploy -Running $false -RollbackStatus 'RolledBack'

        Test-MainPod $deploy.PodStatuses[0] -status 'Unknown' -reason "Possible timeout"
    } -Tag 'Timeout','Sad','t11'

    It "has a temporary startup timeout" {
        $deploy = Deploy-Minimal -PassThru -SkipInit -SkipPreHook -TimeoutSec 60 -RunCount 10 -StartupProbe
        Test-Deploy $deploy -Running $true

        Test-MainPod $deploy.PodStatuses[0]
    } -Tag 'Probe', 'Happy', 't12'

    It "has a startup timeout" {
        $deploy = Deploy-Minimal -PassThru -SkipInit -SkipPreHook -TimeoutSec 10 -RunCount 10 -StartupProbe
        Test-Deploy $deploy -Running $false -RollbackStatus 'RolledBack'

        Test-MainPod $deploy.PodStatuses[0] -status 'Timeout' -reason "Possible timeout"
    } -Tag 'Sad', 'Timeout', 'Probe', 't13'

    It "has a bad probe" {
        $deploy = Deploy-Minimal -PassThru -SkipInit -SkipPreHook -TimeoutSec 120 -Readiness '/fail'
        Test-Deploy $deploy -Running $false -RollbackStatus 'RolledBack'

        Test-MainPod $deploy.PodStatuses[0] -status 'Unknown' -reason "Possible timeout"
        $deploy.PodStatuses[0].LastBadEvents.Count | Should -Be 1
        $deploy.PodStatuses[0].LastBadEvents[0] | Should -BeLike 'Readiness probe failed:*'
    } -Tag 'Sad','Probe', 't14'

    It "has a prehook job top timeout" {
        $deploy = Deploy-Minimal -PassThru -SkipInit -HookRunCount 50 -TimeoutSec 10
        Test-Deploy $deploy -Running $false -podCount 0 -RollbackStatus 'RolledBack'

        # no pod statuses
    } -Tag 'Sad', 'Timeout', 't15'

    It "has an init failure" {
        $deploy = Deploy-Minimal -PassThru -SkipPreHook -InitFail
        Test-Deploy $deploy -Running $false -RollbackStatus 'RolledBack'

        Test-MainPod $deploy.PodStatuses[0] -status 'Crash' -reason "Possible timeout"
    } -Tag 'Sad', 'Crash', 't16'

    It "has init bad config" {
        $deploy = Deploy-Minimal -PassThru -SkipPreHook -InitTag zzz
        Test-Deploy $deploy -Running $false -RollbackStatus 'RolledBack'

        Test-MainPod $deploy.PodStatuses[0] -status 'ConfigError' -reason "Possible timeout"
        $deploy.PodStatuses[0].LastBadEvents.Count | Should -BeGreaterThan 1
        $deploy.PodStatuses[0].LastBadEvents[1] | Should -Be 'Error: ErrImageNeverPull'

    } -Tag 'Sad', 'Crash', 't17'

    It "has an init timeout" {
        $deploy = Deploy-Minimal -PassThru -SkipPreHook -TimeoutSec 5 -InitRunCount 50
        Test-Deploy $deploy -Running $false -RollbackStatus 'RolledBack'

        Test-MainPod $deploy.PodStatuses[0] -status 'Timeout' -reason "Possible timeout"
    } -Tag 'Sad', 'Timeout', 't18'

    It "has prehook job hook timeout" {
        $deploy = Deploy-Minimal -PassThru -SkipInit -HookRunCount 100 -PreHookTimeoutSecs 5
        $global:deploy = $deploy
        $deploy.Running | Should -Be $false
        $deploy.RollbackStatus | Should -Be 'RolledBack'
        $deploy.ReleaseName | Should -Be 'test'

        Test-PreHook $deploy.PreHookStatus -status 'Timeout' -containerStatus 'Running'
    } -Tag 'Timeout','Negative','t19'

    It "has prehook job crash" {
        $deploy = Deploy-Minimal -PassThru -HookFail -TimeoutSecs 20 -PreHookTimeoutSecs 20
        Test-Deploy $deploy -Running $false -PodCount 0 -RollbackStatus 'RolledBack'

        $deploy.PreHookStatus.Status | Should -Be 'Crash'
    } -Tag 'Crash','Sad','t20'

    It "has prehook config error" {
        $deploy = Deploy-Minimal -PassThru -HookTag zzz
        Test-Deploy $deploy -Running $false -PodCount 0 -RollbackStatus 'RolledBack'

        $deploy.PreHookStatus.Status | Should -Be 'ConfigError'
        $deploy.PreHookStatus.LastBadEvents.Count | Should -BeGreaterThan 1
        $deploy.PreHookStatus.LastBadEvents[1] | Should -Be 'Error: ErrImageNeverPull'
    } -Tag 'Config','Sad','t21'

    It "has prehook timeout" {
        $deploy = Deploy-Minimal -PassThru -PreHookTimeoutSecs 5 -HookRunCount 100
        Test-Deploy $deploy -Running $false -PodCount 0 -RollbackStatus 'RolledBack'

        $deploy.PreHookStatus.Status | Should -Be 'Timeout'
    } -Tag 'Config','Sad','t22'

    It "tests error if checking preHook, but not making one" {
        Write-Host (kubectl delete job test-prehook --wait --ignore-not-found) # prev step may have left one
        do {
            Write-Host "Still there >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
            Start-Sleep 1
        } while (Get-PodByJobName test-prehook)
        $deploy = Deploy-Minimal -PassThru -AlwaysCheckPreHook -SkipPreHook -SkipInit -TimeoutSecs 10
        Test-Deploy $deploy -Running $false -PodCount 0 -RollbackStatus 'RolledBack'

    } -Tag 'Config','Sad','t23'

    It "tests taints" {
        $node = k get node -o jsonpath="{.items[0].metadata.name}"
        kubectl taint nodes $node key1=value1:NoSchedule
        try {
            $deploy = Deploy-Minimal -PassThru -SkipPreHook -SkipInit -RunCount 1 -PreHookTimeoutSecs 5 -TimeoutSecs 5
            Test-Deploy $deploy -Running $false -PodCount 1 -RollbackStatus 'RolledBack'
            $deploy.PodStatuses[0].LastBadEvents[0] | Should -BeLike '*schedul*'
        }
        finally {
            kubectl taint nodes $node key1:NoSchedule-
        }
    } -Tag 'Sad','t24'

    It "tests no changes" {
        $deploy1 = Deploy-Minimal -PassThru -SkipPreHook -SkipInit -TimeoutSecs 10 -SkipSetStartTime

        Test-Deploy $deploy1

        Test-MainPod $deploy1.PodStatuses[0]

        $deploy2 = Deploy-Minimal -PassThru -SkipPreHook -SkipInit -TimeoutSecs 10 -SkipSetStartTime

        Test-Deploy $deploy2

        Test-MainPod $deploy2.PodStatuses[0]

        $deploy1.PodStatuses[0].PodName | Should -Be $deploy2.PodStatuses[0].PodName
    } -Tag 'Happy','t25'

    It "times out on huge cpu request" {
        $deploy = Deploy-Minimal -PassThru -SkipInit -SkipPreHook -CpuRequest 1000 -TimeoutSecs 10
        Test-Deploy $deploy -Running $false -RollbackStatus 'RolledBack'

        Test-MainPod $deploy.PodStatuses[0] -status 'Timeout'
    } -Tag 'Sad','t26'

    It "times out on huge cpu request on prehook" {
        $deploy = Deploy-Minimal -PassThru -SkipInit -HookCpuRequest 1000 -TimeoutSecs 10 -PreHookTimeoutSecs 3
        Test-Deploy $deploy -Running $false -RollbackStatus 'RolledBack' -PodCount 0

        Test-PreHook $deploy.PreHookStatus -status 'Timeout'
    } -Tag 'Sad','t27'

    It "tests rollback if uninstalled" {
        helm uninstall test
        $deploy = Deploy-Minimal -PassThru -SkipInit -SkipPreHook -Fail
        Test-Deploy $deploy -Running $false -RollbackStatus 'RolledBack'

        Test-MainPod $deploy.PodStatuses[0] -status 'Crash'
    } -Tag 'Sad','t1000'

    It "tests bad chart name" {
        try {
            Deploy-Minimal -PassThru -SkipInit -SkipPreHook -ChartName zzz
        } catch {
            $_ | Should -BeLike '*Check chart name. No data from kubectl get deploy -l app.kubernetes.io/instance=test,app.kubernetes.io/name=zzz*'
        }
    } -Tag 'Sad','t28'


    It "tests bad service account" {
        $deploy = Deploy-Minimal -PassThru -SkipInit -SkipPreHook -ServiceAccount zzz
        Test-Deploy $deploy -Running $false -RollbackStatus 'RolledBack'

        $deploy.PodStatuses[0].Status | Should -Be 'ConfigError'
        $deploy.PodStatuses[0].PodName | Should -Be '<replica set error>'
        $deploy.PodStatuses[0].LastBadEvents.Count | Should -Be 1
        $deploy.PodStatuses[0].LastBadEvents[0] | Should -BeLike 'Error creating:*serviceaccount "zzz" not found*'

    } -Tag 'Sad','t29'

    It "tests service account without secret access" {
        $deploy = Deploy-Minimal -PassThru -SkipInit -SkipPreHook -ServiceAccount secret-no-reader-service-account
        Test-Deploy $deploy -Running $false -RollbackStatus 'RolledBack'

        $deploy.PodStatuses[0].Status | Should -Be 'ConfigError'
        $deploy.PodStatuses[0].PodName | Should -Be '<replica set error>'
        $deploy.PodStatuses[0].LastBadEvents.Count | Should -Be 1
        $deploy.PodStatuses[0].LastBadEvents[0] | Should -BeLike 'Error creating:*volume with secret.secretName="example-secret" is not allowed because service account secret-no-reader-service-account does not reference that secret*'

    } -Tag 'Sad','t30'

    It "tests service account with secret access" {
        $deploy = Deploy-Minimal -PassThru -SkipInit -SkipPreHook
        Test-Deploy $deploy

        Test-MainPod $deploy.PodStatuses[0]

    } -Tag 'Happy','t31'

}

