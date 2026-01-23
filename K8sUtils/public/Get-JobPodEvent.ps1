<#
.SYNOPSIS
Retrieves events related to a specific Kubernetes job's pod.

.DESCRIPTION
Get events for a pod by finding the job's event that created the pod.

.PARAMETER JobName
The name of the Kubernetes job to query events for.

.PARAMETER Since
The timestamp from which to retrieve events (default is 5 minutes ago).

.EXAMPLE
Get-JobPodEvent -JobName "test-prehook"

Get events for a specific job's pod

.NOTES
This is used when a job kicks off a pod that doesn't start so you can get the events for that pod.
#>
function Get-JobPodEvent {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string] $JobName,
        [DateTime] $Since = (Get-CurrentTime ([TimeSpan]::FromMinutes(-5)))
    )
    Set-StrictMode -Version Latest
    $ErrorActionPreference = "Stop"

    Write-VerboseStatus "Getting events for job '$JobName' since $Since"

    $jobEvents = Get-K8sEvent -ObjectName $JobName -Kind Job
    if (!$jobEvents -ne 0) {
        throw "Failed to get events for job '$JobName'."
    }

    # Filter events after the timestamp
    $filteredJobEvents = @($jobEvents | Where-Object {
        $_.metadata.creationTimestamp -ge $Since
    })
    Write-VerboseStatus "Filtered $($jobEvents.Count - $filteredJobEvents.Count) events by time for job $JobName"

    # Find the event that created the pod (reason = "SuccessfulCreate")
    $createPodEvent = $filteredJobEvents | Where-Object {
        $_.reason -eq "SuccessfulCreate" -and $_.regarding.kind -eq "Job"
    } | Select-Object -Last 1

    if (-not $createPodEvent) {
        Write-VerboseStatus "No 'SuccessfulCreate' event found for job '$JobName'."
        return $null
    }

    # Extract pod name from the message (e.g., "Created pod: test-prehook-xxxxx")
    if ($createPodEvent.note -match "Created pod: (\S+)") {
        $podName = $matches[1]
        Write-VerboseStatus "Job created pod: $podName"
    } else {
        Write-VerboseStatus "Could not extract pod name from creation event message."
        return $null
    }

    Get-K8sEvent -ObjectName $podName -Kind Pod -NoNormal
}
