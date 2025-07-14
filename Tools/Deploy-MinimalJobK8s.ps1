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

.PARAMETER SkipRollbackOnError
If set, don't do a helm rollback on error

.PARAMETER TimeoutSecs
Timeout in seconds for waiting on the pods. Defaults to 600

.PARAMETER PollIntervalSec
Seconds to wait between polls defaults to 5

.PARAMETER ColorType
Color type to use for output, defaults to ANSI

.PARAMETER BadSecret
If set, use a bad secret name for the job

.PARAMETER StartOnly
If set, don't wait for the job to complete, just start it

.PARAMETER Registry
Docker registry to use for the job image, defaults to docker.io

.PARAMETER ActiveDeadlineSeconds
How long to wait for the job to complete, defaults to 30 seconds
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
        [switch] $BadSecret,
        [switch] $StartOnly,
        [string] $Registry = "docker.io",
        [int] $ActiveDeadlineSeconds = 30
    )
    Set-StrictMode -Version Latest
    $ErrorActionPreference = "Stop"
    $imagePullPolicy=$($Registry -eq "docker.io" ? "Never" : "Always")

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
        image: $Registry/init-app:$InitTag
        imagePullPolicy: $imagePullPolicy
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
  backoffLimit: 0 #default is 6
  activeDeadlineSeconds: $ActiveDeadlineSeconds
  ttlSecondsAfterFinished: 600
  template:
    metadata:
      name: "test"
    spec:
      restartPolicy: Never
      containers:
      - name: test-job
        image: "$Registry/init-app:$ImageTag"
        imagePullPolicy: $imagePullPolicy
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

        if ($StartOnly) {
            return
        }
        $logFolder = [System.IO.Path]::GetTempPath()
        Get-JobStatus -JobName "test-job" `
                      -ReplicaCount 1 `
                      -Verbose:$VerbosePreference `
                      -TimeoutSec $TimeoutSecs `
                      -PollIntervalSec $PollIntervalSec `
                      -Namespace "default" `
                      -LogFileFolder $logFolder
        Write-Host "Logs for job are in $logFolder" -ForegroundColor Cyan
    } catch {
        Write-Error "Error! $_`n$($_.ScriptStackTrace)"
    } finally {
        if (!$StartOnly) {
          kubectl delete job test-job --ignore-not-found | Write-Host
        }
    }

}