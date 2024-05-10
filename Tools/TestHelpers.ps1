# mainly used in test, but split out in case you want to use them

function Test-Deploy( $deploy, $running = $true, $podCount = 1 ){
    $deploy.Running | Should -Be $running
    $deploy.ReleaseName | Should -Be 'test'
    if ($podCount) {
        $deploy.PodStatuses.Count | Should -Be $podCount
    } else {
        [bool]$deploy.PodStatuses | Should -Be $false
    }
}

function Test-Pod( $podStatus, $status, $reason, $nameLike, $containerName ) {
    $podStatus.Status | Should -Be $status
    $podStatus.PodName | Should -BeLike $nameLike
    if ($reason -ne "Possible timeout") {
        $podStatus.ContainerStatuses.Count | Should -Be 1
        $podStatus.ContainerStatuses[0].ContainerName | Should -Be $containerName
        $podStatus.ContainerStatuses[0].Status | Should -Be $status
        if ($reason) {
            $podStatus.ContainerStatuses[0].Reason | Should -Be $reason
        }
    }
}

function Test-PreHook( $podStatus,  $status = 'Running', $reason = $null) {
    Test-Pod $podStatus $status $reason 'test-prehook-*' 'pre-install-upgrade-job'
}

function Test-MainPod( $podStatus, $status = 'Running', $reason = $null) {
    Test-Pod $podStatus $status $reason 'test-minimal-*' 'minimal'
}
