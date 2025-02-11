<#
.SYNOPSIS
Test the status of a deployment.

.PARAMETER deploy
The deployment object to test from Invoke-HelmUpgrade.

.OUTPUTS
0 if the deployment is successful, 1 prehook error, 2 if pod, 3 if other
#>
function Test-DeployStatus {
[CmdletBinding()]
param(
    [Parameter(Mandatory,ValueFromPipeline)]
    [PSCustomObject] $deploy
)

process {
    Set-StrictMode -Version Latest

    function Write-FailureMessage($message) {
        switch ($script:ColorType) {
            'DevOps' {
                Write-Plain "##vso[task.logissue type=error]$message "
                Write-Plain "##vso[task.complete result=Failed;]"
                break
            }
            'ANSI' {
                Write-Plain "$($PSStyle.Formatting.Error) $message"
                break
            }
            default {
                Write-Plain $message
            }
        }
    }

    function GetLastBadEvent {
        param(
            [Parameter(Mandatory)]
            [PSCustomObject] $status
        )
        if ((Get-Member -InputObject $status -Name 'LastBadEvents') `
                -and $status.LastBadEvents) {
            $lastBadEvent = $status.LastBadEvents | Select-Object -First 1
            if ($lastBadEvent) {
                Write-FailureMessage "Last bad event: $($lastBadEvent)"
            }
        }
    }
    Write-Verbose "Deploy status is $($deploy | out-string)"
    Write-Verbose "Deploy status JSON: $($deploy | ConvertTo-Json -Depth 5)"

    if ((Get-Member -InputObject $deploy -Name 'PreHookStatus') `
            -and $deploy.PreHookStatus `
            -and $deploy.PreHookStatus.Status -ne 'Completed') {
        Write-FailureMessage "PreHook pod '$($deploy.PreHookStatus.podName)' has status $($deploy.PreHookStatus.Status)"
        GetLastBadEvent $deploy.PreHookStatus
        return 1
    } elseif ((Get-Member -InputObject $deploy -Name 'PodStatuses') `
            -and $deploy.PodStatuses) {
        $badPod = $deploy.PodStatuses | Where-Object { $_.Status -ne 'Running' } | Select-Object -First 1
        if ($badPod) {
            Write-FailureMessage "Pod '$($badPod.PodName)' has status of $($badPod.status)"
            GetLastBadEvent $badPod
            return 2
        }
    } elseif (!$deploy.Running) {
        Write-FailureMessage "Deployment is not running. Check output."
        return 3
    }
    Write-Status "Deployment successful"
    return 0
}

}
