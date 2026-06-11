function Get-TerminalContainerState($pod) {
    $terminalWaitingReasons = @(
        'CrashLoopBackOff', 'ImagePullBackOff', 'ErrImagePull',
        'CreateContainerConfigError', 'InvalidImageName', 'RunContainerError'
    )
    $allStatuses = @()
    if (Get-Member -InputObject $pod.status -Name containerStatuses -ErrorAction SilentlyContinue) {
        $allStatuses += $pod.status.containerStatuses | ForEach-Object { @{ cs = $_; kind = "container" } }
    }
    if (Get-Member -InputObject $pod.status -Name initContainerStatuses -ErrorAction SilentlyContinue) {
        $allStatuses += $pod.status.initContainerStatuses | ForEach-Object { @{ cs = $_; kind = "init container" } }
    }
    foreach ($entry in $allStatuses) {
        $cs = $entry.cs
        if ((Get-Member -InputObject $cs.state -Name waiting -ErrorAction SilentlyContinue) -and $cs.state.waiting) {
            if ($cs.state.waiting.reason -in $terminalWaitingReasons) {
                return @{ ContainerName = $cs.name; Kind = $entry.kind; Reason = $cs.state.waiting.reason; Message = $cs.state.waiting.message }
            }
        }
        if ((Get-Member -InputObject $cs.state -Name terminated -ErrorAction SilentlyContinue) -and $cs.state.terminated) {
            $t = $cs.state.terminated
            if ($t.exitCode -ne 0 -and $t.reason -ne 'Completed') {
                return @{ ContainerName = $cs.name; Kind = $entry.kind; Reason = $t.reason; Message = "exitCode=$($t.exitCode)" }
            }
        }
    }
    return $null
}
