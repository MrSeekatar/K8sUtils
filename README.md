# K8sUtils PowerShell Module <!-- omit in toc -->

This a PowerShell module is for working with Kubernetes and Helm. It was created to solve a problem when using `helm -wait` in a CI/CD pipeline. `-wait` is wonderful in that your pipeline will wait for a successful deployment, but if anything goes wrong, it will wait for the timeout and then return an error. At that point, you may have lost all the logs and events that could help diagnose the problem, and have to re-run the deployment and baby sit it to try to catch the logs or events that causes the timeout.

With `Invoke-HelmUpgrade` you get the similar functionality, but it will capture all the logs and events along the way, and if there is an error, it will return early as possible. No more waiting the 5 or 10 minutes you set on `helm -wait`.

There an infinite number of ways K8s can be configured and error out. This module tries to handle to most common cases, and is appended as more are discovered. It does handle preHooks and initContainers. See below for a list of all the cases that are tested.

> This proved to be very useful when my company created a new K8s cluster, and added deployments to it. As we worked through the many configuration and permission issues, the pipelines failed quickly with full details of the problem. We never had to even check K8s. It was a huge time saver.

## What `Invoke-HelmUpgrade` does

It calls `helm upgrade` without `-wait` and then will poll K8s during the various phases of the deployment capturing events and logs along the way.

```mermaid
flowchart TD
    start([Start]) --> upgrade

    upgrade[Helm upgrade] --> preHook{PreHook?}
    preHook -- Yes --> checkJob[Log preHook\nJob status]
    checkJob --> jobOk{Ok?}

    jobOk -- No --> failed
    jobOk -- Yes --> deploy
    preHook -- No --> deploy
    deploy[Get deployment\n& replicaSet] --> pod

    running -- No --> pod
    pod[Get pod status] -- Running --> running{All pods\nrunning?}
    pod -- Not Running --> checkPod[Log pod\nstatus]
    checkPod --> pod

    pod -- Error ---> failed
    running -- Yes --> ok([OK])
    pod -- Timeout ---> failed{Rollback?}
    failed -- Yes --> rollback([Rollback])
    failed -- No --> exit([End])
```


- [What `Invoke-HelmUpgrade` does](#what-invoke-helmupgrade-does)
- [Kubernetes Manifests](#kubernetes-manifests)
- [run.ps1 Tasks](#runps1-tasks)
- [Links](#links)

## Kubernetes Manifests

In the `DevOps/Kubernetes` folder are the following manifests:

| Name                        | Description                                                                              |
| --------------------------- | ---------------------------------------------------------------------------------------- |
| busy-box.yml                | A busybox pod for testing in service-test namespace                                      |
| manifests1.yml              | Creates a deployment, service and ingress with host my-k8s-example1.com                  |
| manifests2.yml              | Creates a deployment, service and ingress with host my-k8s-example2.com                  |
| powershell.yml              | A PowerShell pod for testing in service-test namespace                                   |
| service-test-ns-service.yml | Create minimal3 service to access service 1 in service-test namespace using ExternalName |

## run.ps1 Tasks

The `run.ps1` script has the following tasks that you can execute with `.\run.ps1 <task>,...`.

| Task            | Description                                                                           |
| --------------- | ------------------------------------------------------------------------------------- |
| applyManifests  | Apply all the manifests in DevOps/manifests to the Kubernetes cluster                 |
| publishK8sUtils | Publish the K8sUtils module to a NuGet repo                                           |
| upgradeHelm[^1] | Upgrade/install the Helm chart in the Kubernetes cluster using `minimal1_values.yaml` |
| uninstallHelm   | Uninstall the Helm chart in the Kubernetes cluster                                    |

[^1]: The `config-and-secret.yaml` manifest must be applied before running this task.


> The [init-app](src/init-app) project is a simple console app used as both an initContainer and Helm pre-install hook. It has switches to run for a time, or to fail.

> `$env:invokeHelmAllowLowTimeouts=1` to allow short timeouts for testing, otherwise will set min to 120s for prehook and 180s for main

The following table shows the testing of starting the app with helm and the various ways it can fail. `Crash` means the pod/job actually crashes. `Config` means the pod/job doesn't even start due to some configuration error such as bad image tag, missing environment variable or mount, etc. The Switch column is the switch to `Deploy-Minimal` to make the app fail in that way.

 | Pre-Hook | Init   | Main     | Handled | `Deploy-Minimal` Switches         |
 | -------- | ------ | -------- | :-----: | --------------------------------- |
 | OK       | OK     | OK       |    ✅    |                                   |
 | OK       | OK     | BadProbe |    ✅    | -Readiness '/fail'                |
 | OK       | OK     | Crash    |    ✅    | -Fail                             |
 | OK       | OK     | Config   |    ✅    | -BadSecret or delete cm or secret |
 | OK       | OK     | Config   |    ✅    | -ImageTag zzz                     |
 | OK       | Crash  | n/a      |    ✅    | -InitFail                         |
 | OK       | Config | n/a      |    ✅    | -InitTag zzz                      |
 | Crash    | n/a    | n/a      |    ✅    | -HookFail                         |
 | Config   | n/a    | n/a      |    ✅    | -HookTag zzz                      |

Other cases

| Description                                  | Handled | `Deploy-Minimal` Switches                                         |
| -------------------------------------------- | :-----: | ----------------------------------------------------------------- |
| Replica increase                             |    ✅    | -Replicas 3                                                       |
| Replica decrease                             |    ✅    | -Replicas 1                                                       |
| PreHook timeout                              |    ✅    | -TimeoutSecs 30 -HookRunCount 60                                  |
| Init container timeout                       |    ✅    | -TimeoutSecs 10 -InitRunCount 40 -SkipPreHook                     |
| Main container liveness timeout              |    ✅    | -TimeoutSecs 10 -RunCount 40 -SkipPreHook                         |
| PreHook Job timeout                          |    ✅    | -SkipInit -HookRunCount 100 -HookTimeoutSecs                      |
| Main container timeout                       |    ✅    | -SkipInit -RunCount 100                                           |
| Another operation in progress                |    ✅    | -SkipInit -HookRunCount 100 in one terminal, -SkipInit in another |
| Main container startup timeout               |    ✅    | -SkipInit -TimeoutSec 10 -RunCount 10 -SkipPreHook -StartupProbe  |
| Main container startup times out a few times |    ✅    | -SkipInit -TimeoutSec 60 -RunCount 10 -SkipPreHook -StartupProbe  |
| PreHook Job `restart: onFailure`             |         |                                                                   |
| PreHook Job `activeDeadlineSeconds`          |         |                                                                   |

### Pester Test Coverage <!-- omit in toc -->

These are the tests in [textMinimalDeploy.tests.ps1](Tools/MinimalDeploy.tests.ps1)

 | Test                                     | `Deploy-Minimal` Switches                                        |
 | ---------------------------------------- | ---------------------------------------------------------------- |
 | Ok, hook, init                           |                                                                  |
 | Ok, hook                                 | -SkipInit                                                        |
 | Ok, init                                 | -SkipPreHook                                                     |
 | Ok                                       | -SkipInit -SkipPreHook                                           |
 | Dry run                                  | -DryRun                                                          |
 | Main crash                               | -SkipInit -SkipPreHook -Fail                                     |
 | Main bad image tag                       | -SkipInit -SkipPreHook -ImageTag zzz                             |
 | Main bad secret name                     | -SkipInit -SkipPreHook -BadSecret                                |
 | Main times out                           | -SkipInit -SkipPreHook -RunCount 100                             |
 | Main startup probe temporarily times out | -SkipInit -SkipPreHook -TimeoutSec 60 -RunCount 10 -StartupProbe |
 | Main startup probe fails                 | -SkipInit -SkipPreHook -TimeoutSec 120 -Readiness '/fail'        |
 | Init container times out                 | -SkipPreHook -TimeoutSec 10 -InitRunCount 50                     |
 | Prehook times out                        | -SkipInit -HookRunCount 100 -PreHookTimeoutSecs 5                |
 | Prehook job crashes                      | -HookFail -TimeoutSecs 20 -PreHookTimeoutSecs 20                 |
 | ?                                        |                                                                  |
 | ?                                        |                                                                  |

### Test helm chart <!-- omit in toc -->

The `DevOps/Helm` folder has a chart and `minimal1_values.yaml` file that can be used to test the helm chart. The `Invoke-HelmUpgrade` function in the PS module will run the upgrade with parameters to control this.

See the preHookJob.yml for details on its configuration. Currently the `helm.sh/hook-delete-policy` is `before-hook-creation` so it will remain out there after the upgrade, but the `ttlSecondsAfterFinished` will delete it after 30s (or so).

Values to set in the minimal to control the tests, all of these can be set with switches to `Deploy-Minimal`:

| Name                   | Values        | Description                                                                                          |
| ---------------------- | ------------- | ---------------------------------------------------------------------------------------------------- |
| failOnStart            | true or false | The image tag to use for the container, defaults to latest, use a bogus value to make a config error |
| runCount               | number        | How many times to run before being ready with 1s delay                                               |
| image.tag              | string        | The image tag to use for the main container                                                          |
| initContainer.runCount | number        | How many times to run before exiting with 1s delay                                                   |
| initContainer.fail     | false or true | If true runs runCount times, then fails                                                              |
| initContainer.imageTag | string        | The image tag to use for the container, defaults to latest, use a bogus value to make a config error |
| preHook.runCount       | number        | How many times to run before exiting with 1s delay                                                   |
| preHook.fail           | false or true | If true runs runCount times, then fails                                                              |
| preHook.imageTag       | string        | The image tag to use for the container, defaults to latest, use a bogus value to make a config error |

## Links

- [K8s doc: DNS](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/) mentions using names like `<serviceName>.<nsName>.svc.cluster.local` to access services in other namespaces.
- [K8s doc: kubectl annotate](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#annotate)
- [K8s doc: patch](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#patch)
- [K8s doc: automount of credentials](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/#opt-out-of-api-credential-automounting)
- [Thorsten Hans Blog about reloading from ConfigMap](https://www.thorsten-hans.com/hot-reload-net-configuration-in-kubernetes-with-configmaps/)
- Ephemeral Containers
  - [K8s doc: Ephemeral Containers](https://kubernetes.io/docs/tasks/debug-application-cluster/debug-running-pod/#ephemeral-container)
  - [Navratan Lal Gupta blog - Debug Kubernetes Pods Using Ephemeral Container](https://medium.com/linux-shots/debug-kubernetes-pods-using-ephemeral-container-f01378243ff)
  - [Ivan Velichko blog - Kubernetes Ephemeral Containers and kubectl debug Command](https://iximiuz.com/en/posts/kubernetes-ephemeral-containers/)
