# mainly used in test, but split out in case you want to use them

function Test-Deploy( $deploy, $running = $true, $podCount = 1, $rollbackStatus = "DeployedOk" ){
    if (!(Get-Member -InputObject $deploy -Name 'Running' -MemberType Property)) {
        Write-Warning "Test-Deploy found that deploy object is missing Running property, full object:"
        Write-Warning ($deploy | ConvertTo-Json -Depth 5)
    }
    $deploy.Running | Should -Be $running
    $deploy.ReleaseName | Should -Be 'test'
    $deploy.RollbackStatus | Should -Be $rollbackStatus
    if ($podCount) {
        $deploy.PodStatuses.Count | Should -Be $podCount
    } else {
        [bool]$deploy.PodStatuses | Should -Be $false
    }
}

function Test-Pod( $podStatus, $status, $containerStatus, $reason, $nameLike, $containerName ) {
    $podStatus.Status | Should -Be $status
    $podStatus.PodName | Should -BeLike $nameLike
    if ($reason -ne "Possible timeout" -and $status -ne 'Timeout') { # timeouts don't save container statuses
        $podStatus.ContainerStatuses | Should -Not -BeNullOrEmpty
        $podStatus.ContainerStatuses.Count | Should -Be 1
        $podStatus.ContainerStatuses[0].ContainerName | Should -Be $containerName
        $podStatus.ContainerStatuses[0].Status | Should -Be $containerStatus
        if ($reason) {
            $podStatus.ContainerStatuses[0].Reason | Should -Be $reason
        }
    }
}

function Test-PreHook( $podStatus, $status = 'Completed', $containerStatus = 'Completed', $reason = $null) {
    Test-Pod $podStatus $status $containerStatus $reason 'test-prehook-*' 'pre-install-upgrade-job'
}

function Test-MainPod( $podStatus, $status = 'Running', $reason = $null) {
    Test-Pod $podStatus -Status $status -ContainerStatus $status -Reason $reason 'test-minimal-*' 'minimal'
}

function Test-Job($jobStatus, $running = $false, $rollbackStatus = "DeployedOk", $status = 'Completed', $reason = $null) {
    $jobStatus.Count | Should -Be 2
    Test-Deploy $jobStatus[0] -running $running -PodCount 0 -rollbackStatus $rollbackStatus
    Test-Pod $jobStatus[1] -status $status -containerStatus $status -reason $reason -nameLike 'test-job-*' -containerName 'pre-install-upgrade-job'
}