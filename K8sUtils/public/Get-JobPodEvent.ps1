<#
.SYNOPSIS
Retrieves events related to a specific Kubernetes job and its associated pod.

.DESCRIPTION
This function queries Kubernetes for events related to a specified job and its created pod.
It filters events based on a provided timestamp and extracts relevant information.

.PARAMETER JobName
The name of the Kubernetes job to query events for.

.PARAMETER FromWhen
The timestamp from which to retrieve events (default is 5 minutes ago).

.EXAMPLE
Get-JobPodEvent -JobName "test-prehook"

Get events for a specific job

.NOTES
This is used when a job kicks off a pod that doesn't start so you can get the events for that pod.
#>
function Get-JobPodEvent {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string] $JobName,
        [DateTime] $FromWhen = (Get-Date).AddMinutes(-5)
    )
    Set-StrictMode -Version Latest
    $ErrorActionPreference = "Stop"

    # Define the start time in RFC3339 format (e.g., 2025-06-13T10:00:00Z)
    $start = $FromWhen.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

    # Step 1: Get events related to the job
    $jobEventsJson = kubectl get events --field-selector "involvedObject.kind=Job,involvedObject.name=$JobName" -o json
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to get events for job '$JobName'."
    }
    $jobEvents = $jobEventsJson | ConvertFrom-Json -Depth 10

    # Filter events after the timestamp
    $filteredJobEvents = $jobEvents.items | Where-Object {
        $eventTime = if ($_.eventTime) { $_.eventTime } else { $_.lastTimestamp }
        $eventTime -ge $start
    }

    # Step 2: Find the event that created the pod (reason = "SuccessfulCreate")
    $createPodEvent = $filteredJobEvents | Where-Object {
        $_.reason -eq "SuccessfulCreate" -and $_.involvedObject.kind -eq "Job"
    } | Select-Object -Last 1

    if (-not $createPodEvent) {
        Write-Verbose "No 'SuccessfulCreate' event found for job '$JobName'."
        return $null
    }

    # Extract pod name from the message (e.g., "Created pod: test-prehook-xxxxx")
    if ($createPodEvent.message -match "Created pod: (\S+)") {
        $podName = $matches[1]
        Write-Verbose "Job created pod: $podName"
    } else {
        Write-Verbose "Could not extract pod name from creation event message."
        return $null
    }

    # Step 3: Get all events for that pod
    $podEventsJson = kubectl get events --field-selector "involvedObject.kind=Pod,involvedObject.name=$podName,type=Warning" -o json
    $podEvents = $podEventsJson | ConvertFrom-Json

    $podEvents.items | ForEach-Object { "$($_.reason): $($_.message)" }

}
