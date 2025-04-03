# Import the script that defines the Deploy-MinimalJobK8s function
BeforeAll {
    Import-Module  $PSScriptRoot\Minimal.psm1 -Force -ArgumentList $true
    Import-Module  $PSScriptRoot\..\K8sUtils\K8sUtils.psm1 -Force -ArgumentList $true

    $env:invokeHelmAllowLowTimeouts = $true

    . $PSScriptRoot\TestHelpers.ps1
}

Describe "Deploys Minimal API" {

    It "runs init ok" {
        $deploy = Deploy-MinimalJobK8s

        Test-Pod $deploy -nameLike 'test-job-*' -containerName 'test-job' -status 'Completed' -containerStatus 'Completed'
        $deploy.PodLogFile | Should -Not -BeNullOrEmpty
        Test-Path $deploy.PodLogFile | Should -Be $true
    } -Tag 'Happy','k1'

    It "runs without init ok" {
        $deploy = Deploy-MinimalJobK8s -SkipInit

        Test-Pod $deploy -nameLike 'test-job-*' -containerName 'test-job' -status 'Completed' -containerStatus 'Completed'
    } -Tag 'Happy','k2'

    It "runs a dry run" {
        $manifest = Deploy-MinimalJobK8s -DryRun
        $manifest | Should -Match "^apiVersion: batch/v1\s+kind: Job"
    } -Tag 'Happy','k6'

    It "has main container crash" {
        $deploy = Deploy-MinimalJobK8s -SkipInit -Fail
        Test-Pod $deploy -nameLike 'test-job-*' -containerName 'test-job' -status 'Crash' -containerStatus 'Crash'
    } -Tag 'Crash','Sad','k7'

    It "has main container has bad image tag" {
        $deploy = Deploy-MinimalJobK8s -SkipInit -ImageTag zzz
        Test-Pod $deploy -nameLike 'test-job-*' -containerName 'test-job' -status 'ConfigError' -containerStatus 'ConfigError'
    } -Tag 'Config','Sad','k8'

    It "has the main container with a bad secret name" {
        $deploy = Deploy-MinimalJobK8s -SkipInit -BadSecret
        Test-Pod $deploy -nameLike 'test-job-*' -containerName 'test-job' -status 'ConfigError' -containerStatus 'ConfigError'
    } -Tag 'Config','Sad','k9'

    It "has the main container too short time out" {
        $deploy = Deploy-MinimalJobK8s -SkipInit -TimeoutSec 3 -RunCount 100
        Test-Pod $deploy -nameLike 'test-job-*' -containerName 'test-job' -status 'Timeout' -containerStatus 'Timeout' -Reason "Possible timeout"
    } -Tag 'Timeout','Sad','k10'

    It "has the main container time out" {
        $deploy = Deploy-MinimalJobK8s -SkipInit -TimeoutSec 10 -RunCount 100
        Test-Pod $deploy -nameLike 'test-job-*' -containerName 'test-job' -status 'Timeout' -containerStatus 'Timeout' -Reason "Possible timeout"
    } -Tag 'Timeout','Sad','k11'

    It "has an init failure" {
        $deploy = Deploy-MinimalJobK8s -InitFail
        Test-Pod $deploy -nameLike 'test-job-*' -containerName 'test-job' -status 'Crash' -containerStatus 'Crash' -Reason "Possible timeout"
    } -Tag 'Sad', 'Crash', 'k16'

    It "has init bad config" {
        $deploy = Deploy-MinimalJobK8s -InitTag zzz
        Test-Pod $deploy -nameLike 'test-job-*' -containerName 'test-job' -status 'ConfigError' -containerStatus 'ConfigError' -Reason "Possible timeout"
    } -Tag 'Sad', 'Crash', 'k17'

    It "has an init timeout" {
        $deploy = Deploy-MinimalJobK8s -TimeoutSec 5 -InitRunCount 50
        Test-Pod $deploy -nameLike 'test-job-*' -containerName 'test-job' -status 'Timeout' -containerStatus 'Timeout' -Reason "Possible timeout"
    } -Tag 'Sad', 'Timeout', 'k18'

    It "gets the pod selector for a job" {
        Deploy-MinimalJobK8s -SkipInit -StartOnly
        $selector = Get-JobPodSelector -JobName test-job
        $selector | Should -Not -BeNullOrEmpty
        $podStatus = Get-PodStatus -PodType Job -Selector $selector
        $podStatus | Should -Not -BeNullOrEmpty
        $podStatus.Status | Should -Be 'Completed'
        kubectl delete job 'test-job' --ignore-not-found
    } -Tag 'Happy','k19'
}
