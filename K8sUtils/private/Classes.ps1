<#
NOTE!!!!

Classes are loaded into a PS Session one time and any change you make are not reflected in the session until you restart the session.

This also means if you make a change to a **function** that uses a class, then reload the psm1, you may be fun errors like
 "Cannot convert the "PodStatus" value of type "PodStatus" to type "PodStatus"."
since the psm1 has a new version of the class and the session has the old version.

Even updating this comment will break it.

When in doubt, restart the session.
#>
enum Status {
    Unknown
    Running
    Timeout
    Crash
    ConfigError
    Completed
}

enum RollbackStatus {
    Unknown
    DeployedOk
    NoChange
    HelmStatusFailed
    Skipped
    RolledBack
}

# state.running means running, has startedAt
# state.terminated means crash, has optional reason, etc. only exitCode req'd
# state.waiting means bad image, missing secret, has optional reason
function mapContainerStatus($containerStatus) {
    if ($containerStatus.ready) {
        return [Status]::Running
    }
    if ((Get-Member -InputObject $containerStatus.state -Name 'waiting') -and $containerStatus.state.waiting) {
        return $containerStatus.state.waiting.reason -eq "CrashLoopBackOff" ? [Status]::Crash : [Status]::ConfigError,($containerStatus.state.waiting.reason)
    }
    if ((Get-Member -InputObject $containerStatus.state -Name 'terminated') -and $containerStatus.state.terminated) {
        return $containerStatus.state.terminated.reason -eq 'completed' ? [Status]::Running : [Status]::Crash,($containerStatus.state.terminated.reason)
    }
    return [Status]::Unknown,"Possible timeout or probe failure"
}

class ContainerStatus
{
    ContainerStatus([string] $ContainerName, [PSCustomObject] $containerStatus)
    {
        $this.ContainerName = $ContainerName
        $this.Status, $this.Reason = mapContainerStatus $containerStatus
    }
    ContainerStatus([string] $ContainerName, [Status] $Status)
    {
        $this.ContainerName = $ContainerName
        $this.Status = $Status
    }
    [string] $ContainerName
    [Status] $Status
    [string] $Reason
}

class PodStatus
{
    PodStatus([string] $PodName)
    {
        $this.PodName = $PodName
        $this.Status = [Status]::Unknown
    }
    [string] $PodName
    [Status] $Status
    [ContainerStatus[]] $ContainerStatuses
    [ContainerStatus[]] $InitContainerStatuses
    [string[]] $LastBadEvents
    [string] $PodLogFile

    [void] DetermineStatus() {
        if (($this.ContainerStatuses | Where-Object { $_ -and $_.Status -eq [Status]::Crash }) -or
            ($this.InitContainerStatuses | Where-Object { $_ -and $_.Status -eq [Status]::Crash }) ) {
            $this.Status = [Status]::Crash
            return
        }
        if (($this.ContainerStatuses | Where-Object { $_ -and $_.Status -eq [Status]::ConfigError }) -or
            ($this.InitContainerStatuses | Where-Object {$_ -and $_.Status -eq [Status]::ConfigError })) {
            $this.Status = ([Status]::ConfigError)
            return
        }
        if (($this.ContainerStatuses | Where-Object { $_ -and $_.Status -eq [Status]::Unknown }) -or
            ($this.InitContainerStatuses | Where-Object {$_ -and $_.Status -eq [Status]::Unknown })) {
            $this.Status = ([Status]::Unknown)
            return
        }
        $this.Status = [Status]::Running
    }
}

class ReleaseStatus
{
    ReleaseStatus() {}
    ReleaseStatus([string] $ReleaseName)
    {
        $this.ReleaseName = $ReleaseName
    }
    [string] $ReleaseName
    [bool] $Running
    [PodStatus[]] $PodStatuses
    [PodStatus] $PreHookStatus
    [RollbackStatus] $RollbackStatus
}