<#
.SYNOPSIS
Get the current time from the Kubernetes API server using verbose output

.PARAMETER Namespace
Kubernetes namespace
#>
function Get-K8sServerTime {
    [CmdletBinding()]
    param(
        [string] $Namespace = "default"
    )

    # Run kubectl with verbose flag to capture the Date header from the response
    # $output = kubectl get --raw /version -v=8 2>&1

    # https://kubernetes.io/docs/reference/using-api/health-checks/#api-endpoints-for-health
    # v=8 is verbose to show http request (to stderr)
    #      https://kubernetes.io/docs/reference/kubectl/quick-reference/#kubectl-output-verbosity-and-debugging
    $output = kubectl get --raw /readyz --v=8 2>&1

    # Parse the Date header from the output
    $dateLine = $output | Select-String -Pattern "Date:" | Select-Object -First 1
    if ($dateLine) {
        # Extract the date string (format: "Date: Thu, 15 Jan 2026 10:30:45 GMT")
        $dateString = $dateLine -replace ".*Date:\s*", ""
        $serverTime = [DateTime]::ParseExact($dateString.Trim(), "ddd, dd MMM yyyy HH:mm:ss 'GMT'", [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal)
        return $serverTime.ToUniversalTime()
    }

    throw "Could not parse server time from kubectl response"
}

# Get pods started after the server time with a specific job-name selector
function Get-PodAfterTime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Selector,
        [string] $Namespace = "default",
        [datetime] $AfterTime = (Get-K8sServerTime)
    )

    # Format time for comparison (ISO 8601 format used by K8s)
    $afterTimeStr = $AfterTime.ToString("yyyy-MM-ddTHH:mm:ssZ")

    # Get pods with the job-name selector
    $podsJson = kubectl get pod --namespace $Namespace --selector $Selector -o json | ConvertFrom-Json

    if (!$podsJson -or !$podsJson.items) {
        return $null
    }

    # Filter pods created after the specified time
    $podsAfterTime = $podsJson.items | Where-Object {
        $_.metadata.creationTimestamp -gt $afterTimeStr
    }

    return $podsAfterTime
}

# Example usage:
# $serverTime = Get-K8sServerTime
# $pods = Get-PodAfterTime -PreHookJobName "my-prehook-job" -Namespace "default" -AfterTime $serverTime
