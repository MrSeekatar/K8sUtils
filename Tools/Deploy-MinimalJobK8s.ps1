<#
.SYNOPSIS
Helper function to deploy a job via K8s

.PARAMETER DryRun
If set, dump out the manifest instead of applying it

.PARAMETER Fail
Have the job fail on start

.PARAMETER InitRunCount
How many times to log a message in the init container, e.g. number of seconds before it exits, defaults to 1

.PARAMETER InitFail
Have the init container fail after InitRunCount loops

.PARAMETER RunCount
How many times to log a message in the job, e.g. number of seconds before it exits, defaults to 1

.PARAMETER ImageTag
Tag to use for the job, defaults to latest

.PARAMETER InitTag
Tag to use for the init container, defaults to latest

.EXAMPLE

#>
function Deploy-MinimalJobK8s {
    [CmdletBinding()]
    param (
        [switch] $DryRun,
        [int] $InitRunCount = 1,
        [switch] $InitFail,
        [int] $RunCount = 1,
        [switch] $Fail,
        [switch] $SkipInit,
        [string] $InitTag = "latest",
        [string] $ImageTag = "latest",
        [int] $TimeoutSecs = 600,
        [int] $PollIntervalSec = 3,
        [ValidateSet("None", "ANSI", "DevOps")]
        [string] $ColorType = "ANSI",
        [switch] $BadSecret
    )
    Set-StrictMode -Version Latest
    $ErrorActionPreference = "Stop"

    $initContainer = $SkipInit ? "" : @"
      initContainers:
      - env:
        - name: RUN_COUNT
          value: "$InitRunCount"
        - name: FAIL
          value: "$InitFail"
        volumeMounts:
        - mountPath: /mt
          name: mt
        image: init-app:$InitTag
        imagePullPolicy: Never
        name: minimal-as-init
        resources: {}
"@

    $secret = $BadSecret ? "example-secret3" : "myconfig__secret3"

    $manifest = @"
apiVersion: batch/v1
kind: Job
metadata:
  name: "test-job"
spec:
  backoffLimit: 0
  activeDeadlineSeconds: 3000
  ttlSecondsAfterFinished: 600
  template:
    metadata:
      name: "test"
    spec:
      restartPolicy: Never
      containers:
      - name: test-job
        image: "init-app:$ImageTag"
        imagePullPolicy: Never
        env:
        - name: RUN_COUNT
          value: "$RunCount"
        - name: FAIL
          value: "$Fail"
        - name: example-secret3
          valueFrom:
            secretKeyRef:
              name: example-secret3
              key: $secret

        volumeMounts:
        - mountPath: /mt
          name: mt
$initContainer
      volumes:
      - name: mt
        emptyDir: {}
"@

    if ($DryRun) {
        Write-Output $manifest
        return
    }
    Write-Verbose $manifest
    $null = kubectl delete job test-job --ignore-not-found # so don't find prev one deployed with helm, which will fail
    try {
        $output = $manifest | kubectl apply -f - -o yaml
        Write-Verbose ($output | Out-String)
        if ($LASTEXITCODE -ne 0) {
            throw "kubectl apply failed"
        }

        $logFile = [System.IO.Path]::GetTempFileName()
        Get-JobStatus -JobName "test-job" `
                      -ReplicaCount 1 `
                      -Verbose:$VerbosePreference `
                      -TimeoutSec $TimeoutSecs `
                      -PollIntervalSec $PollIntervalSec `
                      -Namespace "default" `
                      -LogFilename $logFile
        Write-Host "Logs for job are in $logFile" -ForegroundColor Cyan
    } catch {
        Write-Error "Error! $_`n$($_.ScriptStackTrace)"
    } finally {
        kubectl delete job test-job --ignore-not-found | Write-Host
    }

}