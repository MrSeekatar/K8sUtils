function Get-PodStatusOld {

[CmdletBinding()]
param(
    # [Parameter(Mandatory=$true)]
    [string]$AppName = 'minimal'
)
# get by label --selector app=minimal1
$pods = @(k get pod --no-headers -o custom-columns=T:.metadata.name,S:.status.containerStatuses[0].state | sls "^$AppName-")

Write-Verbose "Pods: $($pods.count)"
foreach ($p in $pods) {
    Write-Verbose "  Pod: $($p)"
    $events = @(kubectl get event --field-selector "involvedObject.name=$($pods[0])" -o json | convertfrom-json)
    foreach ($e in $events) {
        Write-Verbose "Events for pod: $($e.items.count)"
        foreach ($ee in $e.items) {
            Write-Verbose "    Event: $($ee.message)"
        }
    }
}

# minimal1-c497bf648-r5jkk    map[running:map[startedAt:2023-09-10T20:21:07Z]]
# minimal1-c497bf648-r5jkk    map[waiting:map[message:back-off 1m20s restarting failed container=minimal1 pod=minimal1-c497bf648-r5jkk_default(cab26363-bfb3-4a24-af5a-b792ecfe2409) reason:CrashLoopBackOff]]

}
