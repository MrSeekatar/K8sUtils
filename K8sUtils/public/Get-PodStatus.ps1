<#
.SYNOPSIS
Get the status of the pods for a release

.PARAMETER Selector
K8s selector for finding the pods

.PARAMETER ReplicaCount
Number of pods to wait for that match the selector

.PARAMETER PollIntervalSec
Seconds to wait between polls defaults to 5

.PARAMETER TimeoutSecs
Timeout in seconds for waiting on the pods. Defaults to 600

.PARAMETER Namespace
K8s namespace to use, defaults to default

.PARAMETER PodType
If Pod, all containers must be running, otherwise for jobs all must be terminated ok

.PARAMETER LogFileFolder
If specified, pod logs will be written to this folder

.EXAMPLE
$hookStatus = Get-PodStatus -Selector "job-name=$PreHookJobName" `
                                            -Namespace $Namespace `
                                            -TimeoutSec 1 `
                                            -PollIntervalSec $PollIntervalSec `
                                            -PodType PreInstallJob

Get the status of a pre-install job pod

.OUTPUTS
Array of PodStatus objects
#>
function Get-PodStatus {
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Selector,
    [ValidateRange(1, 100)]
    [int] $ReplicaCount = 1,
    [ValidateRange(1, 600)]
    [int] $PollIntervalSec = 5,
    [int] $TimeoutSec = 600,
    [string] $Namespace = "default",
    [ValidateSet("Pod", "PreInstallJob", "Job")]
    [string] $PodType = "Pod",
    [string] $LogFileFolder

)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$runningCount = 0
$runningPods = @{}
$podStatuses = @{}

if ($PodType -eq "PreInstallJob" ) {
    $IsJob = $true
    $okPhase = "Succeeded"
    $prefix = "preHook job pod"
} elseif ($PodType -eq "Job") {
    $IsJob = $true
    $okPhase = "Succeeded"
    $prefix = "job pod"
} else {
    $IsJob = $false
    $okPhase = ,"Running"
    $prefix = "pod"
}

# are all containers in the pod ready?
function allContainersReady($containerStatuses) {

    $readyContainers = @()
    Write-Debug "ContainerStatuses: $($containerStatuses | ConvertTo-Json -Depth 10 -EnumsAsStrings)"
    if ($IsJob) {
        # for a job, all containers need to be complete
        $readyContainers += $containerStatuses | Where-Object { (Get-Member -InputObject $_.state -Name 'terminated') -and $_.state.terminated.reason -eq 'Completed'}
    } else {
        # for deploys all should be running
        $readyContainers += $containerStatuses | Where-Object ready -eq $true
    }
    $podIsReady = $readyContainers.Count -eq $containerStatuses.Count
    Write-VerboseStatus "Checking containerStatuses for $($IsJob ? 'job' : 'NON job'). PodIsReady = $podIsReady"
    return $podIsReady
}

$start = Get-Date
$timeoutEnd = $start.AddSeconds($TimeoutSec)
$logSeconds = "600s"
$extraSeconds = 1 # extra seconds to add to logSeconds to avoid missing something
$lastEventTime = (Get-CurrentTime ([TimeSpan]::FromMinutes(-5)))
$timedOut = $false

Write-Status "Checking status of pods of type $podType that match selector $Selector for ${TimeoutSec}s"
$podCount = 0
while ($runningCount -lt $ReplicaCount -and !$timedOut)
{
    $timedOut = (Get-Date) -gt $timeoutEnd
    Write-VerboseStatus "TimedOut: $timedOut"

    # $pods = kubectl get pod --namespace $Namespace --selector "$LabelName=$AppName" --field-selector "status.phase!=Running" -o json | ConvertFrom-Json
    Write-VerboseStatus "kubectl get pod --namespace $Namespace --selector $Selector --sort-by=.metadata.name -o json"
    $pods = kubectl get pod --namespace $Namespace --selector $Selector --sort-by=.metadata.name -o json | ConvertFrom-Json

    if (!$pods) {
        throw "No data from kubectl get pod --namespace $Namespace --selector $Selector"
    }
    $pods = $pods.items
    Write-VerboseStatus "Got $($pods.Count) pods from kubectl get pod --namespace $Namespace --selector $Selector"
    $podCount = $pods.Count
    Write-VerboseStatus ( "    $($pods.metadata.name -join ',')" )

    # Handle odd case when a pod is a pod in $podStatuses that is no longer in $pods
    #   - remove it from $podStatuses
    #   - get its events and logs for diagnostics
    $goners = $podStatuses.Keys | Where-Object { $_ -notin $pods.metadata.name }
    if ($goners) {
        foreach ($goner in $goners) {
            Write-Warning "Pod '$goner' is no longer returned by selector $Selector. Removing from podStatuses."
            $podStatuses.Remove($goner)
            $null = Get-AndWriteK8sEvent -Prefix $prefix -PodName $goner `
                                                    -Namespace $Namespace `
                                                    -LogLevel warning `
                                                    -FilterStartupWarnings

            $null = Write-PodLog -Prefix $prefix -PodName $goner -Namespace $Namespace -LogLevel warning -HasInit:$HasInit -LogFileFolder $LogFileFolder
        }
    }

    $i = 0
    foreach ($pod in $pods) {

        $i += 1
        if ($runningPods[$pod.metadata.name]) {
            continue # this pod is already completed
        }

        if (!$podStatuses[$pod.metadata.name]) {
            $podStatuses[$pod.metadata.name] = [PodStatus]::new($pod.metadata.name)
        }

        $HasInit = [bool](Get-Member -InputObject $pod.spec -Name initContainers -ErrorAction SilentlyContinue)
        Write-VerboseStatus "Pod $($pod.metadata.name) has init container: $HasInit."

        if (!(Get-Member -InputObject $pod.status -Name containerStatuses)) {
            Write-Status "Pod $($pod.metadata.name) has no status.containerStatuses. May not be schedulable yet." -LogLevel warning
            Write-Debug "Pod:`n$($pod | ConvertTo-Json -Depth 10)"
            if (!$timedOut) {
                continue
            }
            $podStatuses[$pod.metadata.name].Status = [Status]::Timeout

            # write final events and logs for this pod
            Write-VerboseStatus "Calling Get-AndWriteK8sEvent for pod $($pod.metadata.name) with LogLevel ok and FilterStartupWarnings"
            $podStatuses[$pod.metadata.name].LastBadEvents = Get-AndWriteK8sEvent -Prefix $prefix -PodName $pod.metadata.name `
                                                                            -Namespace $Namespace `
                                                                            -PassThru `
                                                                            -LogLevel error `
                                                                            -FilterStartupWarnings
            # no logs since no containers
            break
        }

        $containers = @($pod.status.containerStatuses).Count
        $readyContainers = @($pod.status.containerStatuses | Where-Object ready -eq $true).Count
        Write-VerboseStatus "ReplicaCount: $ReplicaCount RunningCount: $RunningCount PodCount: $($pods.Count)"

        Write-Status "Checking $prefix $i/${ReplicaCount} $prefix $($pod.metadata.name) in $($pod.status.phase) phase" -LogLevel normal -Length 0
        Write-Status "       $readyContainers/$containers containers ready. $([int](((Get-Date) - $start).TotalSeconds))s elapsed of ${TimeoutSec}s." -LogLevel normal -Length 0

        if ($VerbosePreference -eq 'Continue' ) {
            $pod | ConvertTo-Json -Depth 10 | Out-File (Join-Path ([System.IO.Path]::GetTempPath()) "pod.json")
        }

        Write-VerboseStatus "Expected phase is $okPhase. Pod's phase is $($pod.status.phase)"
        if ($pod.status.phase -eq $okPhase) {
            Write-VerboseStatus "  $prefix $($pod.metadata.name) status is $($pod.status.phase)"
            if (allContainersReady $pod.status.containerStatuses) {

                $status = $IsJob ? [Status]::Completed : [Status]::Running
                Write-Status "$prefix $($pod.metadata.name) has all containers ready or completed. Status is $status"

                $runningCount += 1
                $runningPods[$pod.metadata.name] = $true

                $podStatuses[$pod.metadata.name].Status = $status
                $podStatuses[$pod.metadata.name].ContainerStatuses = @($pod.status.containerStatuses | ForEach-Object { [ContainerStatus]::new($_.name, $status) })
                if ($HasInit) {
                    $podStatuses[$pod.metadata.name].InitContainerStatuses = @($pod.status.initContainerStatuses | ForEach-Object { [ContainerStatus]::new($_.name, $status) })
                }

                # write final events and logs for this pod
                Write-VerboseStatus "Calling Get-AndWriteK8sEvent for pod $($pod.metadata.name) with LogLevel ok and FilterStartupWarnings"
                $podStatuses[$pod.metadata.name].LastBadEvents = Get-AndWriteK8sEvent -Prefix $prefix -PodName $pod.metadata.name `
                                                                                -Namespace $Namespace `
                                                                                -PassThru `
                                                                                -LogLevel ok `
                                                                                -FilterStartupWarnings

                $podStatuses[$pod.metadata.name].PodLogFile = Write-PodLog -Prefix $prefix -PodName $pod.metadata.name -Namespace $Namespace -LogLevel ok -HasInit:$HasInit -LogFileFolder $LogFileFolder
                continue
            } else {
                Write-VerboseStatus "Pod $($pod.metadata.name) is ready (phase = $okPhase), but pod containerStatuses are: $($pod.status.containerStatuses | out-string)"
            }
        }

        if ($timedOut) {
            Get-AndWriteK8sEvent -Prefix $prefix -PodName $pod.metadata.name -Namespace $Namespace -LogLevel warning -FilterStartupWarnings
            $podStatuses[$pod.metadata.name].PodLogFile = Write-PodLog -Prefix $prefix -PodName $pod.metadata.name -Namespace $Namespace -LogLevel warning -HasInit:$HasInit -LogFileFolder $LogFileFolder
            break
        }

        # check for any errors since not ready yet
        $lastEventTime = (Get-CurrentTime)
        $events = Get-PodEvent -Namespace $Namespace -PodName $pod.metadata.name
        if ($events) {
            $errors = @($events | Where-Object { $_.type -ne "Normal" -and $_.message -notlike "Startup probe failed:*" -and $_.reason -ne "FailedScheduling"})
            Write-VerboseStatus "Got $($errors.count) error of $($events.count) events for pod $($pod.metadata.name) "
            if ($errors -or $pod.status.phase -eq "Failed" ) {
                Write-Status "Pod $($pod.metadata.name) has $($errors.count) errors" -LogLevel Error
                # write final events and logs for this pod
                Write-VerboseStatus "Calling Get-AndWriteK8sEvent for pod $($pod.metadata.name) with LogLevel Error"
                $podStatuses[$pod.metadata.name].LastBadEvents = Get-AndWriteK8sEvent -Prefix $prefix -PodName $pod.metadata.name -Namespace $Namespace -LogLevel Error -PassThru
                $podStatuses[$pod.metadata.name].PodLogFile = Write-PodLog -Prefix $prefix -PodName $pod.metadata.name -Namespace $Namespace -LogLevel Error -HasInit:$HasInit -LogFileFolder $LogFileFolder

                # get latest pod status since sometimes get containerCreating status here
                $name = $pod.metadata.name
                Write-VerboseStatus "kubectl get pod --namespace $Namespace $name -o json"
                $podJson = kubectl get pod --namespace $Namespace $name -o json
                $pod = $podJson | ConvertFrom-Json
                if (!$pod -or !(Get-Member -InputObject $pod -Name metadata)) {
                    Write-Warning "Unexpected response from kubectl get pod --namespace $Namespace $name JSON is: '$podJson'"
                    # throw "Unexpected response from kubectl get pod --namespace $Namespace $name"
                    return $podStatuses.Values
                }

                $podStatuses[$pod.metadata.name].ContainerStatuses = @($pod.status.containerStatuses | ForEach-Object {
                        Write-Debug "Pod status: $($_ | ConvertTo-Json -Depth 10)"
                        [ContainerStatus]::new($_.name, $_) })
                if ($HasInit) {
                    $podStatuses[$pod.metadata.name].InitContainerStatuses = @($pod.status.initContainerStatuses | ForEach-Object { [ContainerStatus]::new($_.name, $_) })
                }
                $podStatuses[$pod.metadata.name].DetermineStatus()
                Write-Debug "Get-PodStatus returning $($podStatuses[$pod.metadata.name] | ConvertTo-Json -Depth 10 -EnumsAsStrings)"
                return $podStatuses.Values

            } elseif ($VerbosePreference -eq 'Continue') {
                Write-VerboseStatus "No errors found in events for pod $($pod.metadata.name) yet"

                Get-AndWriteK8sEvent -Prefix $prefix -PodName $pod.metadata.name -Since $lastEventTime -Namespace $Namespace
                $podStatuses[$pod.metadata.name].PodLogFile = Write-PodLog -Prefix $prefix -PodName $pod.metadata.name -Since $logSeconds -Namespace $Namespace -HasInit:$HasInit
            }
       } # else no events
       # TODO we've seen case where pod.status.containerStatuses.state.waiting has
       #   message: secret "eventhub-disabled-bootstrap-servers" not found
       #   reason: CreateContainerConfigErrorreason: ImagePullBackOff
       # but nothing in events. Local testing always has events.
    } # end foreach pod

    if ($runningCount -ge $ReplicaCount) {
        Write-Status "All ${prefix}s ($runningCount/$ReplicaCount) that matched selector $Selector are running`n" -Length 0 -LogLevel normal
        break
    }

    if ($timedOut) {
        break
    }
    Write-VerboseStatus "Sleeping $PollIntervalSec second$($PollIntervalSec -eq 1 ? '': 's'). Running Count = $runningCount ReplicaCount = $ReplicaCount"
    Start-Sleep -Seconds $PollIntervalSec
    $logSeconds = "$($PollIntervalSec + $extraSeconds)s"
} # end while check pods

$ok = [bool]($runningCount -ge $ReplicaCount)
if (!$ok) {
    Write-VerboseStatus "Times: $(Get-Date) -lt $($timeoutEnd) Values count: $($podStatuses.Values.Count)"
    Write-Status "Error getting status for pods that matched selector $Selector after $([int](((Get-Date) - $start).TotalSeconds))s" `
                -Length 0 `
                -LogLevel Error
    Write-Status "    RunningCount: $runningCount ReplicaCount: $ReplicaCount PodCount: $podCount Ok: $ok TimedOut: $timedOut" `
                -Length 0 `
                -LogLevel Error
    if ($podStatuses.Count -eq 0) {
        $status = [PodStatus]::new("<no pods found>")
        $status.Status = [Status]::Timeout
        $podStatuses["<no pods found>"] = $status
    }
    $podStatuses.Values | ForEach-Object {
        if ($_.PodName -and !$_.LastBadEvents) {
            # try one more to see if there are errors in the case where the pod disappeared due to deadline exceeded, etc.
            $events = Get-AndWriteK8sEvent -Prefix $prefix -PodName $_.PodName -Since ($lastEventTime - (New-TimeSpan -Minutes 5)) -Namespace $Namespace -NoNormal -PassThru
            if ($events) {
                $_.LastBadEvents = $events
            }
        }
        $_.Status = [Status]::Timeout
    }

}

return $podStatuses.Values
}
