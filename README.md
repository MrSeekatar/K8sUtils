# K8sUtils PowerShell Module <!-- omit in toc -->

A time-saving PowerShell module for deploying Helm charts in CI/CD pipelines. It captures all the logs and events of a deployment in the pipeline's output. In the event of a failure, it will return early, instead of timing out.

> This proved to be very useful at my company when updating pipelines to deploy to a new K8s cluster. As we worked through the many configuration and permission issues, the pipelines failed quickly with full details of the problem. We rarely had to check K8s. It was a huge time saver.

- [Commands](#commands)
- [How `Invoke-HelmUpgrade` Works](#how-invoke-helmupgrade-works)
- [Using `Invoke-HelmUpgrade`](#using-invoke-helmupgrade)
- [Using `Invoke-HelmUpgrade` in an Azure DevOps Pipeline](#using-invoke-helmupgrade-in-an-azure-devops-pipeline)
- [Testing `Invoke-HelmUpgrade`](#testing-invoke-helmupgrade)
- [Pod States](#pod-states)
- [Container States](#container-states)

This module was created to solve a problem when using `helm -wait` in a CI/CD pipeline. `-wait` is wonderful feature in that your pipeline will wait for a successful deployment instead of returning after tossing the manifests to K8s. If anything goes wrong, however, it will wait until the timeout and then return just a timeout error. At that point, you may have lost all the logs and events that could help diagnose the problem and then have to re-run the deployment and baby sit it to try to catch the logs or events from K8s.

With `Invoke-HelmUpgrade` you get similar functionality, but it will capture all the logs and events along the way, and if there is an error, it will return early as possible. No more waiting the 5 or 10 minutes you set on `helm -wait`.

There are an infinite number of ways helm and its K8s manifests can be configured and error out. `Invoke-HelmUpgrade` tries to handle the most common cases, and is amended as more are discovered. It does handle Helm pre-install [hooks](https://helm.sh/docs/topics/charts_hooks/) (preHooks) and K8s [initContainers](https://kubernetes.io/docs/concepts/workloads/pods/init-containers/). See [below](#tested-scenarios) for a list of all the cases that are covered.

One thing that is required to get prehook logs is to set the `helm.sh/hook-delete-policy` to `before-hook-creation` in the prehook job manifest. This will keep the job around after the upgrade, and the `ttlSecondsAfterFinished` will delete it after 30s, if desired. This is done in the [minimal chart](DevOps\Helm\templates\preHookJob.yaml#L19).

## Commands

Here's a list of the commands in the module with a brief description. Use `help <command>` to get more details.

| Command              | Description                                            |
| -------------------- | ------------------------------------------------------ |
| Get-DeploymentStatus | Get the status of the pods for a deployment            |
| Get-PodByJobName     | Get a pod give a K8s job name                          |
| Get-PodEvent         | Get all the K8s events for a pod                       |
| Get-PodStatus        | Get the status of a pod, dumping events and logs       |
| Invoke-HelmUpgrade   | Calls `helm upgrade` and polls K8s for events and logs |
| Set-K8sConfig        | Sets type of output wanted for Invoke-HelmUpgrade      |

## How `Invoke-HelmUpgrade` Works

`Invoke-HelmUpgrade` calls `helm upgrade` without `-wait` and then will poll K8s during the various phases of the deployment, capturing events and logs along the way.

```mermaid
flowchart TD
    start([Start]) --> upgrade

    upgrade[helm upgrade] --> preHook{pre-install\nhook?}
    preHook -- Yes --> checkJob[Log preHook\nJob events\n& logs]
    checkJob -- Poll\nuntil end\nor timeout --> checkJob
    checkJob --> jobOk{Succeeded?}

    jobOk -- Failed\nor timeout --> failed
    jobOk -- Yes --> hasDeploy{Deploy?}
    preHook -- No --> hasDeploy{Deploy?}
    hasDeploy -- Yes --> deploy
    hasDeploy -- No --> exit2([End Ok])
    deploy[Get deployment\n& replicaSet] --> pod

    running -- No --> pod
    pod[Get pod status] -- Running --> running{All pods\nrunning?}
    pod -- Not Running --> checkPod[Log pod\nstatus]
    checkPod --> pod

    pod -- Failed ---> failed
    running -- Yes --> ok([End OK])
    pod -- Timeout ---> failed{-SkipRollback?}
    failed -- No --> rollback([Rollback])
    failed -- Yes --> exit([End\nwith error])
    rollback --> exit
```

## Using `Invoke-HelmUpgrade`

You can run `Invoke-HelmUpgrade` from the command line or in a CI/CD pipeline. It has a number of parameters to control its behavior, and `help Invoke-HelmUpgrade` will give you all the details.

## Using `Invoke-HelmUpgrade` in an Azure DevOps Pipeline

Before the script can run, you need to do the following in your pipeline's Job:

- `kubectl login`
- `helm registry login`
- `Install-Module K8sUtils` if you've registered it or `Import-Module` if you have it locally

I've included a sanitized, version of a yaml [template](DevOps/AzureDevOpsTask/helm-upgrade.yml) used in an Azure DevOps pipeline. You can adapt it to your needs. It does the following.

1. Logs into K8s using a AzDO Service Connection
2. Logs into the Helm registry (with retries)
3. Pulls K8sUtils from a private NuGet repo, and installs it
4. Runs a task to update the `values.yaml` file with parameter values
5. Runs `Invoke-HelmUpgrade` with the updated `values.yaml` file

## Testing `Invoke-HelmUpgrade`

Tests can be run locally using [Rancher Desktop](https://rancherdesktop.io/) or [Docker Desktop](https://www.docker.com/products/docker-desktop/) with Kubernetes enabled. The Pester test scripts use `Minimal.psm1` helper module to deploy the [minimal-api](https://github.com/MrSeekatar/minimal-api) ASP.NET application, which must be built and pushed to local Docker.

### run.ps1 Tasks <!-- omit in toc -->

The `run.ps1` script has the following tasks that you can execute with `.\run.ps1 <task>,...`.

| Task            | Description                                                                          |
| --------------- | ------------------------------------------------------------------------------------ |
| applyManifests  | Apply all the manifests in DevOps/manifests to the Kubernetes cluster                |
| publishK8sUtils | Publish the K8sUtils module to a NuGet repo                                          |
| test            | Test the `Invoke-HelmUpgrade` function with various scenarios with Pester            |
| upgradeHelm[^1] | Upgrade/install the Helm chart in the Kubernetes cluster using `minimal_values.yaml` |
| uninstallHelm   | Uninstall the Helm chart in the Kubernetes cluster                                   |

[^1]: The `config-and-secret.yaml` manifest must be applied before running this task.

### Kubernetes Manifests <!-- omit in toc -->

In the `DevOps/Kubernetes` folder are the following manifests:

| Name                   | Description                                                             |
| ---------------------- | ----------------------------------------------------------------------- |
| config-and-secret.yaml | ConfigMap and Secret for the minimal1 deployment                        |
| manifests1.yml         | Creates a deployment, service and ingress with host my-k8s-example1.com |
| manifests2.yml         | Creates a deployment, service and ingress with host my-k8s-example2.com |

> Set `$env:invokeHelmAllowLowTimeouts=1` to allow short timeouts for testing, otherwise will set minimum to 120s for prehook and 180s for main. Setting `$env:TF_BUILD=$true` will simulate running in an Azure DevOps pipeline and change header and footer output.

### Tested Scenarios <!-- omit in toc -->

The following table shows the scenarios of deploying the app with helm and the various ways it can fail. `Crash` means the pod/job actually crashes. `Config` means the pod/job doesn't even start due to some configuration error such as bad image tag, missing environment variable or mount, etc.

 | Pre-Hook |  Init   |   Main   | Test                                      |
 | :------: | :-----: | :------: | ----------------------------------------- |
 |    OK    |   OK    |    OK    | hook, init ok                             |
 |    OK    |    -    |    OK    | without init ok                           |
 |    -     |   OK    |    OK    | without prehook ok                        |
 |    -     |    -    |    OK    | without init or prehook ok                |
 |    OK    |    -    |    -     | with prehook only ok                      |
 |    -     |    -    | BadProbe | a bad probe                               |
 |    -     |    -    |  Crash   | main container crash                      |
 |    -     |    -    |  Config  | the main container with a bad secret name |
 |    -     |    -    |  Config  | main container has bad image tag          |
 |    OK    |  Crash  |    -     | an init failure                           |
 |    OK    | Config  |    -     | init bad config                           |
 |    -     | Timeout |    -     | init timeout                              |
 |  Crash   |    -    |    -     | prehook job crash                         |
 |  Config  |    -    |    -     | prehook config error                      |
 | Timeout  |    -    |    -     | prehook timeout                           |
 |    -     |    -    | Timeout  | the main container time out               |
 |    -     |    -    | Timeout  | the main container too short time out     |
 |    -     |    -    |    -     | a dry run                                 |
 |    -     |    -    |    OK    | a temporary startup timeout               |
 |    -     |    -    | Timeout  | a startup timeout                         |
 |    -     |    -    |    -     | a prehook job top timeout                 |
 |    -     |    -    |    -     | an init timeout                           |
 |    -     |    -    |    -     | prehook job hook timeout                  |

### Other Scenarios <!-- omit in toc -->

These test cases are difficult to test or yet to be covered with tests.

| Description                                  | Manual<br>Test | `Deploy-Minimal` Switches                                                |
| -------------------------------------------- | :------------: | ------------------------------------------------------------------------ |
| Replica increase                             |       ✅        | -Replicas 3                                                              |
| Replica decrease                             |       ✅        | -Replicas 1                                                              |
| Main container liveness timeout              |       ✅        |                                                                          |
| Another operation in progress                |       ✅        | -SkipInit -HookRunCount 100 in one terminal, -SkipInit in another        |
| Main container startup timeout               |       ✅        | -SkipInit -TimeoutSec 10 -RunCount 10 -SkipPreHook -StartupProbe         |
| Main container startup times out a few times |       ✅        | -SkipInit -TimeoutSec 60 -RunCount 10 -SkipPreHook -StartupProbe         |
| PreHook Job `restart: onFailure`             |                |                                                                          |
| PreHook Job `activeDeadlineSeconds`          |                |                                                                          |
| Object not owned by Helm                     |       ✅        | `helm uninstall test` then `k apply -f .\DevOps\Kubernetes\deploy-without-helm.yaml` then deploy|

### Test helm chart <!-- omit in toc -->

The `DevOps/Helm` folder has a chart and `minimal_values.yaml` file that can be used to test the helm chart.

See the `preHookJob.yml` for details on its configuration. Currently the `helm.sh/hook-delete-policy` is `before-hook-creation` so it will remain out there after the upgrade, but the `ttlSecondsAfterFinished` will delete it after 30s (or so).

These values in the values file can be set with switched to `Deploy-Minimal` to test various scenarios.

| Name                   | Values        | Description                                                                                          |
| ---------------------- | ------------- | ---------------------------------------------------------------------------------------------------- |
| deployment.enabled     | true or false | Should the main container be deployed?                                                               |
| env.failOnStart        | true or false | The image tag to use for the container, defaults to latest, use a bogus value to make a config error |
| env.runCount           | number        | How many times to run before being ready with 1s delay                                               |
| image.tag              | string        | The image tag to use for the main container                                                          |
| initContainer.fail     | false or true | If true runs runCount times, then fails                                                              |
| initContainer.imageTag | string        | The image tag to use for the container, defaults to latest, use a bogus value to make a config error |
| initContainer.runCount | number        | How many times to run before exiting with 1s delay                                                   |
| preHook.fail           | false or true | If true runs runCount times, then fails                                                              |
| preHook.imageTag       | string        | The image tag to use for the container, defaults to latest, use a bogus value to make a config error |
| preHook.runCount       | number        | How many times to run before exiting with 1s delay                                                   |
| readinessPath          | string        | Path the the readiness URL for K8s to call                                                           |
| replicaCount           | number        | Number of replica to run, defaults to 1                                                              |

## Pod States

To be "ok" we look for `Succeeded` for pre-install jobs and `Running` for the main pod. For both we look for `Failed`, and if it doesn't reach an "ok" state within the timeout, we return a timeout error.

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

Within a pod, the container states are tracked

```mermaid
stateDiagram
    [*] --> Waiting
    Waiting --> Running
    Running --> Terminated: Succeeded or Failed
    Terminated --> [*]
```
