<#
.SYNOPSIS
Get the current time from the Kubernetes API server using verbose output

.PARAMETER Namespace
Kubernetes namespace

.OUTPUTS
Returns the current server time as a DateTime object in UTC. If it cannot be determined, returns local system time in UTC.
#>
function Get-K8sServerTime {
    [CmdletBinding()]
    param(
        [string] $Namespace = "default"
    )
    Set-StrictMode -Version Latest
    $ErrorActionPreference = "Stop"

    # Run kubectl with v=8 verbose flag to capture the Date header from the response

    # https://kubernetes.io/docs/reference/using-api/health-checks/#api-endpoints-for-health
    # v=8 is verbose to show http request (to stderr)
    #      https://kubernetes.io/docs/reference/kubectl/quick-reference/#kubectl-output-verbosity-and-debugging
    $output = kubectl get --raw /readyz --v=8 2>&1

    # Parse the Date header from the output
    $dateLine = $output | Select-String -Pattern "Date:" | Select-Object -First 1
    if ($dateLine) {
        # Extract the date string (format: "Date: Thu, 15 Jan 2026 10:30:45 GMT")
        $dateString = $dateLine -replace ".*Date:\s*", ""
        $dateFormat = "ddd, dd MMM yyyy HH:mm:ss 'GMT'"
        $serverTime = [DateTime]::UtcNow
        if ([DateTime]::TryParseExact($dateString.Trim(), $dateFormat,
                                        [System.Globalization.CultureInfo]::InvariantCulture,
                                        [System.Globalization.DateTimeStyles]::AssumeUniversal,
                                        [ref]$serverTime)) {
            return $serverTime.ToUniversalTime()
        }
    }

    Write-Warning "Could not parse server time from kubectl response using UTC now."
    return Get-Date -AsUTC

}


<#
.SYNOPSIS
Get pods created after a specified time

.PARAMETER Selector
Kubernetes label selector to filter pods (e.g., "job-name=my-job")

.PARAMETER AfterTime
DateTime object specifying the minimum creation time for pods

.PARAMETER Namespace
Kubernetes namespace to search in (default: "default")

.OUTPUTS
Returns an array of pod objects created after the specified time, or null if no pods found.
#>
function Get-PodAfterTime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Selector,
        [Parameter(Mandatory)]
        [DateTime] $AfterTime,
        [string] $Namespace = "default"
    )
    Set-StrictMode -Version Latest
    $ErrorActionPreference = "Stop"

    # Get pods with the job-name selector
    $pods = kubectl get pod --namespace $Namespace --selector $Selector -o json | ConvertFrom-Json

    if (!$pods -or !$pods.items) {
        return $null
    }

    # Filter pods created after the specified time
    $podsAfterTime = $pods.items | Where-Object {
        Write-Verbose "Comparing timestamp for pod $($_.metadata.name): creationTimestamp: $($_.metadata.creationTimestamp) > ${afterTime}?"
        $_.metadata.creationTimestamp -ge $afterTime
    }

    return @($podsAfterTime)
}


