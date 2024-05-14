<#
.SYNOPSIS
Get the status of the pods for a release

.PARAMETER Selector
K8s select for finding the pods

.PARAMETER ReplicaCount
Number of pods to wait for that match the selector

.PARAMETER PollIntervalSec
Seconds to wait between polls defaults to 5

.PARAMETER TimeoutSecs
Timeout in seconds for waiting on the pods. Defaults to 600

.PARAMETER Namespace
K8s namespace to use, defaults to default

.PARAMETER OutputFile
File to write output to in addition to the console

.PARAMETER IsJob
Is this pod a job's pod

.EXAMPLE
An example

.OUTPUTS
$True if all pods are running, $False if not
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
    [string] $OutputFile,
    [switch] $IsJob

)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$runningCount = 0
$runningPods = @{}
$podStatuses = @{}
$global:pods = $podStatuses
$createdTempFile = !$OutputFile

if ($IsJob) {
    $phases = "Succeeded","Running" # running for timeout
    $prefix = "preHook job pod"
} else {
    $phases = ,"Running"
    $prefix = "pod"
}

function podReady($containerStatuses) {
    if ($IsJob) {
        return $true # !($containerStatuses | Where-Object { (Get-Member -InputObject $_.state -Name 'terminated') -and  $_.state.terminated.reason -ne 'Completed'})
    } else {
        Write-Verbose "Checking containerStatuses for NON job"
        return !($containerStatuses| Where-Object ready -ne $true)  # all containers ready
    }
}

if (!$OutputFile) {
    $OutputFile = Get-TempLogFile
}

$start = Get-Date
$timeoutEnd = $start.AddSeconds($TimeoutSec)
$logSeconds = "600s"
$extraSeconds = 1 # extra seconds to add to logSeconds to avoid missing something
$lastEventTime = (Get-Date).AddMinutes(-5)
$timedOut = $false
while ($runningCount -lt $ReplicaCount -and !$timedOut)
{
    $timedOut = (Get-Date) -gt $timeoutEnd

    # $pods = kubectl get pod --namespace $Namespace --selector "$LabelName=$AppName" --field-selector "status.phase!=Running" -o json | ConvertFrom-Json
    $pods = kubectl get pod --namespace $Namespace --selector $Selector --sort-by=.metadata.name -o json | ConvertFrom-Json

    if (!$pods) {
        throw "No data from kubectl get pod --namespace $Namespace --selector $Selector"
    }
    $pods = $pods.items
    Write-Verbose "Got $($pods.Count) pods from kubectl get pod --namespace $Namespace --selector $Selector"

    $i = 0
    foreach ($pod in $pods) {

        if (!$podStatuses[$pod.metadata.name]) {
            $podStatuses[$pod.metadata.name] = [PodStatus]::new($pod.metadata.name)
        }

        $HasInit = [bool](Get-Member -InputObject $pod.spec -Name initContainers -ErrorAction SilentlyContinue)
        Write-Verbose "Pod $($pod.metadata.name) has init container: $HasInit."

        if ($timedOut) {
            Write-PodEvent -Prefix $prefix -PodName $pod.metadata.name -Namespace $Namespace -PassThru -LogLevel ok -FilterStartupWarnings
            Write-PodLog -Prefix $prefix -PodName $pod.metadata.name -Namespace $Namespace -LogLevel ok -HasInit:$HasInit
            continue
        }

        $i += 1
        if ($runningPods[$pod.metadata.name]) {
            continue
        }

        $containers = $pod.status.containerStatuses.Count
        $readyContainers = @($pod.status.containerStatuses | Where-Object ready -eq $true).Count
        Write-Verbose "ReplicaCount: $ReplicaCount RunningCount: $RunningCount PodCount: $($pods.Count)"

        Write-Status "Checking $prefix $i/${ReplicaCount} $prefix $($pod.metadata.name) in $($pod.status.phase) phase" -LogLevel normal -Length 0
        Write-Status "       $readyContainers/$containers containers ready. $([int](((Get-Date) - $start).TotalSeconds))s elapsed of ${TimeoutSec}s." -LogLevel normal -Length 0
        Write-Host ""

        if ($VerbosePreference -eq 'Continue' ) {
            $pod | ConvertTo-Json -Depth 10 | Out-File (Join-Path ([System.IO.Path]::GetTempPath()) "pod.json")
        }

        Write-Verbose "Phases are $($phases -join ',') Phase is $($pod.status.phase)"
        if ($pod.status.phase -in $phases) {
            # "  $prefix $($pod.metadata.name) status is $($pod.status.phase)" | Tee-Object $OutputFile -Append | Write-Host
            if (!$runningPods[$pod.metadata.name] -and
                (podReady $pod.status.containerStatuses)) {

                "  $prefix $($pod.metadata.name) has all containers ready or completed or timed out`n" | Tee-Object $OutputFile -Append | Write-Host
                $runningCount += 1
                $runningPods[$pod.metadata.name] = $true
                $podStatuses[$pod.metadata.name].Status = [Status]::Running
                $podStatuses[$pod.metadata.name].ContainerStatuses = @($pod.status.containerStatuses | ForEach-Object { [ContainerStatus]::new($_.name, [Status]::Running) })
                if ($HasInit) {
                    $podStatuses[$pod.metadata.name].InitContainerStatuses = @($pod.status.initContainerStatuses | ForEach-Object { [ContainerStatus]::new($_.name, [Status]::Running) })
                }

                # write final events and logs for this pod
                Write-Verbose "Calling Write-PodEvent for pod $($pod.metadata.name) with LogLevel ok and FilterStartupWarnings"
                $podStatuses[$pod.metadata.name].LastBadEvents = Write-PodEvent -Prefix $prefix -PodName $pod.metadata.name -Namespace $Namespace -PassThru -LogLevel ok -FilterStartupWarnings
                Write-PodLog -Prefix $prefix -PodName $pod.metadata.name -Namespace $Namespace -LogLevel ok -HasInit:$HasInit
                continue
            } else {
                Write-Verbose "Pod $($pod.metadata.name) is ready, but pod containerStatuses are: $($pod.status.containerStatuses  | out-string)"
            }
        }

        $lastEventTime = Get-Date
        Write-Verbose "kubectl get events --namespace $Namespace --field-selector `"involvedObject.name=$($pod.metadata.name)`" -o json"
        $events = kubectl get events --namespace $Namespace --field-selector "involvedObject.name=$($pod.metadata.name)" -o json | ConvertFrom-Json
        if ($events) {
            $errors = @($events.items | Where-Object { $_.type -ne "Normal" -and $_.message -notlike "Startup probe failed:*"})
            Write-Verbose "Got $($events.items.count) events for pod $($pod.metadata.name) "
            Write-Verbose "Got $($errors.count) errors"
            if ($errors -or $pod.status.phase -eq "Failed" ) {
                # write final events and logs for this pod
                Write-Verbose "Calling Write-PodEvent for pod $($pod.metadata.name) with LogLevel Error"
                $podStatuses[$pod.metadata.name].LastBadEvents = Write-PodEvent -Prefix $prefix -PodName $pod.metadata.name -Namespace $Namespace -LogLevel Error -PassThru
                Write-PodLog -Prefix $prefix -PodName $pod.metadata.name -Namespace $Namespace -LogLevel Error -HasInit:$HasInit

                $podStatuses[$pod.metadata.name].ContainerStatuses = @($pod.status.containerStatuses | ForEach-Object {
                        Write-Verbose ($_ | ConvertTo-Json -Depth 10)
                        [ContainerStatus]::new($_.name, $_) })
                if ($HasInit) {
                    $podStatuses[$pod.metadata.name].InitContainerStatuses = @($pod.status.initContainerStatuses | ForEach-Object { [ContainerStatus]::new($_.name, [Status]::Crash) })
                }
                $podStatuses[$pod.metadata.name].DetermineStatus()
                Write-Verbose "Get-PodStatus returning $($podStatuses[$pod.metadata.name] | ConvertTo-Json -Depth 10 -EnumsAsStrings)"
                return $podStatuses.Values
            } else {
                # "  No errors found for pod $($pod.metadata.name) yet`n" | Tee-Object $OutputFile -Append | Write-Host

                # write intermediate events and logs for this pod
                if ($VerbosePreference -eq 'Continue') {
                    Write-PodEvent -Prefix $prefix -PodName $pod.metadata.name -Since $lastEventTime -Namespace $Namespace
                    Write-PodLog -Prefix $prefix -PodName $pod.metadata.name -Since $logSeconds -Namespace $Namespace -HasInit:$HasInit
                }
            }
       }
    } # end foreach pod

    if ($runningCount -ge $ReplicaCount) {
        Write-Status "All ${prefix}s ($runningCount/$ReplicaCount) that matched selector $Selector are running`n" -Length 0 -Char '-' -LogLevel normal
        break
    }
    if ($timedOut) {
        break
    }
    Write-Verbose "Sleeping $PollIntervalSec second$($PollIntervalSec -eq 1 ? '': 's'). Running Count = $runningCount ReplicaCount = $ReplicaCount"
    Start-Sleep -Seconds $PollIntervalSec
    $logSeconds = "$($PollIntervalSec + $extraSeconds)s"
} # end while check pods

$ok = [bool]($runningCount -ge $ReplicaCount)
if (!$ok) {
    Write-Verbose "$(Get-Date) -lt $($timeoutEnd)"
    Write-Status "Timed out waiting $([int](((Get-Date) - $start).TotalSeconds))s for pods that matched selector $Selector RunningCount: $runningCount ReplicaCount: $ReplicaCount $ok" `
                -Length 0 `
                -LogLevel Error
}
if ($createdTempFile) {
    Write-Host "Output was written to $OutputFile"
}

return $podStatuses.Values
}
