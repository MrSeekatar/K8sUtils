# K8sUtils PowerShell Module <!-- omit in toc -->

K8sUtils is a time-saving PowerShell module for deploying Helm charts and jobs in CI/CD pipelines to Kubernetes (K8s). It captures all the logs and events of a deployment in the pipeline's output. In the event of a failure, it will return early, instead of timing out. For sample output, see the [wiki](https://github.com/MrSeekatar/K8sUtils/wiki).

It has been tested on MacOS, Windows, and Linux.

> This proved very useful at my company when updating pipelines to deploy to a new K8s cluster. As we worked through the many configuration and permission issues, the pipelines failed quickly with full details of the problem. We rarely had to check K8s. It was a huge time saver.

- [Commands](#commands)
- [Using `Invoke-HelmUpgrade`](#using-invoke-helmupgrade)
  - [Using `Invoke-HelmUpgrade` in an Azure DevOps Pipeline](#using-invoke-helmupgrade-in-an-azure-devops-pipeline)
- [Using `Get-JobStatus`](#using-get-jobstatus)
- [How `Invoke-HelmUpgrade` Works](#how-invoke-helmupgrade-works)
- [Testing `Invoke-HelmUpgrade`](#testing-invoke-helmupgrade)
  - [Running the Pester Tests](#running-the-pester-tests)
- [Pod Phases](#pod-phases)
- [Container States](#container-states)
- [Pre-Install Hook Job Timeout Settings](#pre-install-hook-job-timeout-settings)
- [Links](#links)

This module was created to solve a problem when using `helm --wait` in a CI/CD pipeline. `--wait` is a wonderful feature that waits for a successful deployment instead of returning immediately after sending the manifests to K8s. If anything goes wrong, with `--wait` Helm will wait until the timeout and then return a timeout error to the pipeline. At that point, you may have lost all the logs that could help diagnose the problem and then have to re-run the deployment and babysit it to try to catch the logs from K8s.

With `Invoke-HelmUpgrade` you get similar functionality, but it will capture all the logs and events along the way, and if there is an error, it will return as early as possible. No more waiting the 5 or 10 minutes you set on `helm --wait`.

It seems like there are an infinite number of ways Helm and its K8s manifests can be configured and error out. `Invoke-HelmUpgrade` tries to handle the most common cases, and is amended as more are discovered. It does handle Helm pre-install [hooks](https://helm.sh/docs/topics/charts_hooks/) (preHooks) and K8s [initContainers](https://kubernetes.io/docs/concepts/workloads/pods/init-containers/). See [below](#tested-scenarios) for a list of all the covered cases.

For the script to get Helm pre-install hook job's output you must set the [helm.sh/hook-delete-policy](https://helm.sh/docs/topics/charts_hooks/#hook-deletion-policies) to `before-hook-creation` in the job's manifest. This will keep the job around after the upgrade. If you want to clean it up [automatically](https://kubernetes.io/docs/concepts/workloads/controllers/ttlafterfinished/), set `ttlSecondsAfterFinished`. The [minimal chart](DevOps/Helm/templates/preHookJob.yaml#L19) demonstrates this.

## Commands

The following table lists the commands in the module. Most are called by `Invoke-HelmUpgrade`, but are available for other uses. `help <command>` will show more details.

| Command              | Description                                            |
| -------------------- | ------------------------------------------------------ |
| Add-Annotation       | Helper to add an annotation to a K8s object            |
| Convert-Value        | Substitutes variables in a file with placeholders      |
| Get-DeploymentStatus | Get the status of the pods for a deployment            |
| Get-JobPodEvent      | Get the events for a pod started by a job              |
| Get-JobPodSelector   | Get the selector for pods for a job                    |
| Get-JobStatus        | Get the status and logs of a K8s job                   |
| Get-PodByJobName     | Get a pod given a K8s job name                         |
| Get-PodEvent         | Get all the K8s events for a pod                       |
| Get-PodStatus        | Get the status of a pod, dumping events and logs       |
| Invoke-HelmUpgrade   | Calls `helm upgrade` and polls K8s for events and logs |
| Set-K8sUtilsConfig   | Sets type of output wanted for Invoke-HelmUpgrade      |

## Using `Invoke-HelmUpgrade`

You can run `Invoke-HelmUpgrade` from the command line or a CI/CD pipeline. It has a number of parameters to control its behavior, and `help Invoke-HelmUpgrade` will give you all the details. Here's an example using a pre-install hook.

It will log everything it does, as well as K8s events, and pod logs. The events and logs will be output as shown in the [wiki](https://github.com/MrSeekatar/K8sUtils/wiki).

```powershell
$status = Invoke-HelmUpgrade -ValueFile "minimal_values.yaml" `
                             -ChartName "minimal" `
                             -ReleaseName "test"
                             -PreHookJobName "test-prehook"
```

`$status` will be an object that looks like this, serialized to JSON.

```json
{
  "ReleaseName": "test",
  "Running": true,
  "PodStatuses": [
    {
      "PodName": "test-minimal-984b8b9fb-zhst5",
      "Status": "Running",
      "ContainerStatuses": [
        {
          "ContainerName": "minimal",
          "Status": "Running"
        }
      ],
      "InitContainerStatuses": [
        {
          "ContainerName": "init-container-app",
          "Status": "Running"
        }
      ],
      "LastBadEvents": null,
      "PodLogFile": "/var/folders/wt/48syr7hn5qs3qw_vbs0gl3l00000gn/T/test-minimal-984b8b9fb-zhst5.log"
    }
  ],
  "PreHookStatus": {
    "PodName": "test-prehook-x8vdp",
    "Status": "Completed",
    "ContainerStatuses": [
      {
        "ContainerName": "pre-install-upgrade-job",
        "Status": "Completed"
      }
    ],
    "InitContainerStatuses": [
      {
        "ContainerName": "init-container-app",
        "Status": "Completed"
      }
    ],
    "LastBadEvents": null,
    "PodLogFile": "/var/folders/wt/48syr7hn5qs3qw_vbs0gl3l00000gn/T/test-prehook-x8vdp.log"
  },
  "RollbackStatus": "DeployedOk"
}
```

### Using `Invoke-HelmUpgrade` in an Azure DevOps Pipeline

Before the script can run, you need to do the following in your pipeline's Job:

- `kubectl login`
- `helm registry login`
- `Install-Module K8sUtils` if you've registered it or `Import-Module` if you have it locally

I've included a sanitized, version of a yaml [template](DevOps/AzureDevOpsTask/helm-upgrade.yml) used in an Azure DevOps pipeline. You can adapt it to your needs. It does the following.

1. Logs into K8s using a AzDO Service Connection
1. Installs K8sUtils
1. Runs a task to update the `values.yaml` file with environment variables
1. Runs `Invoke-HelmUpgrade` with the updated `values.yaml` file

## Using `Get-JobStatus`

If you have a job that you want to check the status of, you can use `Get-JobStatus`. It will log everything it does, as well as K8s events, and pod logs. Sample output is on the [wiki](https://github.com/MrSeekatar/K8sUtils/wiki#prehook-output).

```powershell
# minimal parameters
$status = Get-JobStatus -JobName "test-job"
```

`$status` will be an object that looks like this, serialized to JSON.

```json
{
  "PodName": "test-job-qcqfw",
  "Status": "Completed",
  "ContainerStatuses": [
    {
      "ContainerName": "test-job",
      "Status": "Completed",
      "Reason": null
    }
  ],
  "InitContainerStatuses": [
    {
      "ContainerName": "minimal-as-init",
      "Status": "Completed",
      "Reason": null
    }
  ],
  "LastBadEvents": null,
  "PodLogFile": "/var/folders/wt/48syr7hn5qs3qw_vbs0gl3l00000gn/T/test-job-qcqfw.log"
}
```

## How `Invoke-HelmUpgrade` Works

`Invoke-HelmUpgrade` calls `helm upgrade` without `-wait` and then will poll K8s during the various phases of the deployment, capturing events and logs along the way.

```mermaid
flowchart TD
    start([Start]) --> upgrade

    upgrade[helm upgrade] --> preHook{pre-install<br/>hook?}
    preHook -- Yes --> hookComplete{Exited or<br/>timed out?}
    hookComplete -- No --> checkJob[Log events<br/>& logs]
    hookComplete -- Yes --> jobOk{Succeeded?}
    checkJob -- wait a bit --> hookComplete

    jobOk -- Failed<br/>or timeout --> failed
    jobOk -- Yes --> hasDeploy{Deploy?}
    preHook -- No --> hasDeploy{Deploy?}
    hasDeploy -- Yes --> deploy
    hasDeploy -- No --> exit2([End Ok])
    deploy[Get deployment<br/>& replicaSet] --> pod

    running -- No --> pod
    pod[Get pods' statuses] -- Running --> running{All pods<br/>running?}
    pod -- Not Running --> checkPod[Log pod<br/>status]
    checkPod --> pod

    pod -- Failed ---> failed
    running -- Yes --> ok([End OK])
    pod -- Timeout ---> failed{-SkipRollback?}
    failed -- No --> rollback[Rollback]
    failed -- Yes --> exit([End<br/>with error])
    rollback --> exit
```

## Testing `Invoke-HelmUpgrade`

Tests can be run locally using [Rancher Desktop](https://rancherdesktop.io/), Azure Kubernetes Services, or [Docker Desktop](https://www.docker.com/products/docker-desktop/) with Kubernetes enabled. There are Pester test scripts that use the `Minimal.psm1` helper module to deploy the [minimal-api](https://github.com/MrSeekatar/minimal-api) ASP.NET application, which must be built and pushed to local Docker (or cloud's container registry).

### run.ps1 Tasks <!-- omit in toc -->

The `run.ps1` script has the following tasks that you can execute with `.\run.ps1 <task>,...`. It has a `KubeContext` parameter that defaults to `rancher-desktop`. (Aliased as `context` and `kube-context` for you muscle memory.)

| Task            | Description                                                                              |
| --------------- | ---------------------------------------------------------------------------------------- |
| applyManifests  | Apply all the required test manifests in DevOps/manifests to the Kubernetes cluster      |
| publishK8sUtils | Publish the K8sUtils module to a NuGet repo                                              |
| test            | Run Pester to test `Invoke-HelmUpgrade` with various scenarios with Pester               |
| testJob         | Run Pester to test creating a job with Helm with various scenarios with Pester           |
| testJobK8s      | Run Pester to test creating a job with a K8s manifest with various scenarios with Pester |
| upgradeHelm[^1] | Upgrade/install the Helm chart in the Kubernetes cluster using `minimal_values.yaml`     |
| uninstallHelm   | Uninstall the test Helm chart in the Kubernetes cluster                                  |

### Running the Pester Tests

Each test task listed above run for quite a while and creates tons of output as well as a summary and the end so you know which tests failed and why. When test new changes, I usually run each one, or a few separately. The `-tag` parameter allows you to tests with one or more tags (see the *.tests.ps1 files). By default it will run against `rancher-desktop` K8s configuration, but you can override that with parameters. Here's running test t2 against AKS.

```powershell
./run.ps1 test -tag t2 -KubeContext widget-aks-test-sc -Registry widget.azurecr.io
```

[^1]: The `applyManifests` task must be run one time before this task.

### Kubernetes Manifests <!-- omit in toc -->

In the `DevOps/Kubernetes` folder are the following manifests:

| Name                     | Description                                                  |
| ------------------------ | ------------------------------------------------------------ |
| config-and-secret.yaml   | ConfigMap and Secret for the minimal1 deployment             |
| deploy-without-helm.yaml | Used for testing without Helm                                |
| lock-down-secrets.yml    | Creates service accounts and roles for testing secret access |

> Set `$env:invokeHelmAllowLowTimeouts=1` to allow short timeouts for testing, otherwise it will set the minimum to 120s for pre-install hook and 180s for main. Setting `$env:TF_BUILD=$true` will simulate running in an Azure DevOps pipeline and change header and footer output format.

### Tested Scenarios <!-- omit in toc -->

The following table shows the scenarios of deploying the app with Helm and the various ways it can fail. `Crash` means the pod/job actually crashes. `Config` means the pod/job doesn't even start due to a configuration error such as a bad image tag, missing environment variable or mount, etc.

 | Pre-Hook |  Init   |   Main   | Test                                         |
 | :------: | :-----: | :------: | -------------------------------------------- |
 |    OK    |   OK    |    OK    | hook, init ok                                |
 |    OK    |    -    |    OK    | without init ok                              |
 |    -     |   OK    |    OK    | without pre-install hook ok                  |
 |    -     |    -    |    OK    | without init or pre-install hook ok          |
 |    OK    |    -    |    -     | with pre-install hook only ok                |
 |    -     |    -    | BadProbe | a bad probe                                  |
 |    -     |    -    |  Crash   | main container crash                         |
 |    -     |    -    |  Config  | the main container with a bad secret name    |
 |    -     |    -    |  Config  | main container has bad image tag             |
 |    OK    |  Crash  |    -     | an init failure                              |
 |    OK    | Config  |    -     | init bad config                              |
 |    -     | Timeout |    -     | init timeout                                 |
 |  Crash   |    -    |    -     | pre-install hook job crash                   |
 |  Config  |    -    |    -     | pre-install hook config error                |
 | Timeout  |    -    |    -     | pre-install hook timeout                     |
 |    -     |    -    | Timeout  | the main container time out                  |
 |    -     |    -    | Timeout  | the main container too short time out        |
 |    -     |    -    |    -     | a dry run                                    |
 |    -     |    -    |    OK    | a temporary startup timeout                  |
 |    -     |    -    | Timeout  | a startup timeout                            |
 |    -     |    -    |    -     | a pre-install hook job top timeout           |
 |    -     |    -    |    -     | an init timeout                              |
 |    -     |    -    |    -     | pre-install hook job hook timeout            |
 | Timeout  |    -    |    -     | pre-install hook Job `activeDeadlineSeconds` |

### Other Scenarios <!-- omit in toc -->

These scenarios are difficult to test or yet to be covered with tests, but can be manually verified.

| Description                                  | Manual<br>Test | `Deploy-Minimal` Switches                                                                        |
| -------------------------------------------- | :------------: | ------------------------------------------------------------------------------------------------ |
| Replica increase                             |       ✅        | -Replicas 3                                                                                      |
| Replica decrease                             |       ✅        | -Replicas 1                                                                                      |
| Main container liveness timeout              |       ✅        |                                                                                                  |
| Another operation in progress                |       ✅        | -SkipInit -HookRunCount 100 in one terminal, -SkipInit in another                                |
| Main container startup timeout               |       ✅        | -SkipInit -TimeoutSec 10 -RunCount 10 -SkipPreHook -StartupProbe                                 |
| Main container startup times out a few times |       ✅        | -SkipInit -TimeoutSec 60 -RunCount 10 -SkipPreHook -StartupProbe                                 |
| pre-install hook Job `restart: onFailure`    |                |                                                                                                  |
| Object not owned by Helm                     |       ✅        | `helm uninstall test` then `k apply -f .\DevOps\Kubernetes\deploy-without-helm.yaml` then deploy |

### Test Helm chart <!-- omit in toc -->

The `DevOps/Helm` folder has a chart and `minimal_values.yaml` file that can be used to test the Helm chart.

See the `preHookJob.yml` for details on its configuration. Currently the `helm.sh/hook-delete-policy` is `before-hook-creation` so it will remain out there after the upgrade, but the `ttlSecondsAfterFinished` will delete it after 30s (or so).

These values in the values file can be set with switches to `Deploy-Minimal` to test various scenarios.

| Name                     | Values        | Description                                                                                          |
| ------------------------ | ------------- | ---------------------------------------------------------------------------------------------------- |
| deployment.enabled       | true or false | Should the main container be deployed?                                                               |
| env.failOnStart          | true or false | The image tag to use for the container, defaults to latest, use a bogus value to make a config error |
| env.runCount             | number        | How many times to run before being ready with 1s delay                                               |
| image.tag                | string        | The image tag to use for the main container                                                          |
| initContainer.fail       | false or true | If true runs runCount times, then fails                                                              |
| initContainer.imageTag   | string        | The image tag to use for the container, defaults to latest, use a bogus value to make a config error |
| initContainer.runCount   | number        | How many times to run before exiting with 1s delay                                                   |
| jobActiveDeadlineSeconds | number        | Active deadline seconds for the pre-install hook job                                                 |
| preHook.create           | false or true | If true runs runs the pre-install hook job                                                           |
| preHook.fail             | false or true | If true runs runCount times, then fails                                                              |
| preHook.imageTag         | string        | The image tag to use for the container, defaults to latest, use a bogus value to make a config error |
| preHook.runCount         | number        | How many times to run before exiting with 1s delay                                                   |
| readinessPath            | string        | Path the the readiness URL for K8s to call                                                           |
| registry                 | string        | Container registry for pulling images.                                                               |
| replicaCount             | number        | Number of replica to run, defaults to 1                                                              |
| resources.requests.cpu   | number        | CPU request for manifest                                                                             |
| serviceAccount.name      | string        | Service account to use for the deployment, defaults to empty string                                  |

## Pod Phases

To be "ok" we look for `Succeeded` for pre-install jobs and `Running` for the main pod. For both, we look for `Failed` and if it doesn't reach an "ok" state within the timeout, we return a timeout error. Stored in `pod.status.phase`. See the [K8s doc](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#pod-phase) for more details.

```mermaid
stateDiagram
    [*] --> Pending
    Pending --> Running: Pod scheduled
    Running --> Succeeded
    Running --> Failed
    Failed --> [*]
    Succeeded --> [*]
    Unknown
```

## Container States

Within a pod, the container states are tracked in `pod.status.containerStatuses[].state`. Depending on the state, different fields are populated. See the [K8s doc](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#container-states) for more details.

- `Waiting` has: reason, message
- `Terminated` has: containerID, exitCode, finishedAt, reason, message, signal, startedAt
- `Running` has: startedAt

```mermaid
stateDiagram
    [*] --> Waiting
    Waiting --> Running
    Running --> Terminated: Succeeded or Failed
    Terminated --> [*]
```

## Pre-Install Hook Job Timeout Settings

The job has a `activeDeadlineSeconds` setting that will kill the job and its pod after the specified number of seconds. This is true for whether it is running, or failing such as with an image pull error. This takes precedence over the `backoffLimit` setting, which is the number of times to retry the job before giving up.

When the job is a pre-install hook, the `helm install --timeout` value comes into play. There are two scenarios to consider:

| Scenario                              | Helm install error                  | State                                              |
| ------------------------------------- | ----------------------------------- | -------------------------------------------------- |
| `activeDeadlineSeconds` < `--timeout` | Deadline exceeded                   | No job or pod. Must look at Events                 |
| `activeDeadlineSeconds` > `--timeout` | timed out waiting for the condition | Job and pod may still be running, or trying to run |

```powershell
# deadline exceeded error, no logs from pre-hook job
Deploy-Minimal -HookRunCount 100 -PreHookTimeoutSecs 10 -activeDeadlineSeconds 5

# timeout error, logs from pre-hook job available
Deploy-Minimal -HookRunCount 100 -PreHookTimeoutSecs 5 -activeDeadlineSeconds 10
```

## Links

- K8s Doc
  - [Init Containers](https://kubernetes.io/docs/concepts/workloads/pods/init-containers/)
  - [Pod Lifecycle](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/)
  - [Jobs doc](https://kubernetes.io/docs/concepts/workloads/controllers/job/#job-termination-and-cleanup) anchor on "Job Termination and Cleanup"
- Helm Doc
  - [Helm Hooks](https://helm.sh/docs/topics/charts_hooks/)
