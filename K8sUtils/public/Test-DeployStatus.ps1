<#
.SYNOPSIS
Test the status of a deployment.

.PARAMETER deploy
The deployment object to test from Invoke-HelmUpgrade.

.OUTPUTS
$true if the deployment is successful, $false otherwise.
#>
function Test-DeployStatus {
[CmdletBinding()]
param(
    [Parameter(Mandatory,ValueFromPipeline)]
    [PSCustomObject] $deploy
)

process {
    Set-StrictMode -Version Latest

    function WriteMessage($message) {
        switch ($script:ColorType) {
            'DevOps' {
                Write-Host "##vso[task.logissue type=error]$message "
                Write-Host "##vso[task.complete result=Failed;]"
                break
            }
            'ANSI' {
                Write-Host $PSStyle.Formatting.Error $message
                break
            }
            default {
                Write-Host $message
            }
        }
    }

    function GetLastBadEvent {
        param(
            [Parameter(Mandatory)]
            [PSCustomObject] $status
        )
        if ((Get-Member -InputObject $status -Name 'LastBadEvents' -MemberType NoteProperty) `
                -and $status.LastBadEvents) {
            $lastBadEvent = $status.LastBadEvents | Select-Object -First 1
            if ($lastBadEvent) {
                WriteMessage "Last bad event: $($lastBadEvent)"
            }
        }
    }

    if ((Get-Member -InputObject $deploy -Name 'PreHookStatus' -MemberType NoteProperty) `
            -and $deploy.PreHookStatus `
            -and $deploy.PreHookStatus.Status -ne 'Running') {
        WriteMessage "PreHook pod '$($deploy.PreHookStatus.podName)' has status $($deploy.PreHookStatus.Status)"
        GetLastBadEvent $deploy.PreHookStatus
        return $false
    } elseif ((Get-Member -InputObject $deploy -Name 'PodStatuses' -MemberType NoteProperty) `
            -and $deploy.PodStatuses) {
        $badPod = $deploy.PodStatuses | Where-Object { $_.Status -ne 'Running' } | Select-Object -First 1
        if ($badPod) {
            WriteMessage "Pod '$($badPod.PodName)' has status of $($badPod.status)"
            GetLastBadEvent $badPod
            return $false
        }
    } elseif ($deploy.Status -ne 'Running') {
        WriteMessage "Deployment status is $($deploy.Status)"
        return $false
    }
    Write-Host "Deployment successful"
    return $true
}

}
