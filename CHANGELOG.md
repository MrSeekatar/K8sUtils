# Change Log

## [1.0.27] 2024-11-7

### Added

- Better handling error case when the chart name is invalid
- Better error handling with replica set gets errors during deployment

### Fixed

- Color of messages in a group match the group
- If a pod is 'waiting' and we try to get the logs it is no longer an error message

### Updated

- Get-PodEvent was renamed to Get-K8sEvent, and Get-PodEvent is an alias for it.
- Get-ReplicaSetEvent and Get-RsEvent are also an aliases for Get-K8sEvent

## [1.0.26] 2024-9-24

### Added

- Show release numbers on rollback messages
- Most data on Get-PodStatus output if not pods were found
- More tests for unscheduled pods for memory requests

### Fixed

- Avoid extra loop in Get-PodStatus when a timeout occurs

## [1.0.25] 2024-9-10

### Fixed

- Write-Footer wasn't writing `endgroup` in all cases.
- Removed errant Write-Footer

## [1.0.24] 2024-8-28

### Added

- Support for the NO_COLOR environment variable. https://no-color.org/
- Invoke-HelmUpgrade has -Quiet switch to suppress logging a list of parameters at start. Before it would log only on -Verbose

### Fixed

- Event output's width could be truncated in AzDO log output
- A warning was logged if `Get-PodEvent` returned no events after filtering

## [1.0.23] 2024-8-5

### Added

- Test cases for when nothing changes in a deployment
- Verbose logging of most kubectl commands
- `LogFileFolder` parameter to `Invoke-HelmUpgrade`, `Get-DeploymentStatus`, `Get-JobStatus`, `Get-PodStatus`, and `Write-PodLog`
- `--wait` to helm rollback
- `ToString` to `PodStatus` class for better viewing of the output object

### Fixed

- Handle case when duplicate env vars of different case and JSON conversion fails
- Bug when rolling back on first install

### Updated

- `Get-DeploymentStatus` now uses jsonpath filter to get the replicaset for the deploy, instead of filtering in PowerShell
- `Write-PodLog` won't write an error if the pod is in ContainerCreating state

## [1.0.21] 2024-7-15

### Fixed

- Erroring out in case when no events are returned from a pod, which may be valid

### Updated

- `Get-PodStatus` has better handling for scheduling errors, such as taints, memory, etc.
- Logging improvements:
  - Footer always matches the header now
  - Use box drawing characters in header and footer to be cleaner
  - Removed output file logging code since `Start-Transcript` works fine
  - Removed timestamps for `TF_BUILD` environment since it's already in the log

## [1.0.18] 2024-7-12

### Added

- Get-JobStatus added to check the status of a K8s job
- Better support in `Get-PodStatus` for checking the status of a job started via Helm or a kubectl apply

### Updated

- Code cleanup
- Get-PodStatus delays timeout check until after one last check
- Get-PodStatus uses deployment's revision instead of creationTimestamp to get the current rs since rollback may make an older one active
- Get-PodStatus checks to see if status has containerStatues since have seen it not be there
- Get-PodStatus doesn't consider an event of FailedScheduling as a failure

## [1.0.15] 2024-6-25

### Fixed

- Falsely errors out if no pre-install hook
- Stop if no pre-install hook, but told to check for it.

### Updated

- Get a pods latest status on error since may report last state as containerCreating since it's a bit stale

## [1.0.14] 2024-6-24

### Added

- Verbose logging for all parameters
- Prerelease support for `run.ps1` publishing

### Fixed

- If helm exits with an error, no longer keeps going.

### Updated

- Improved detection of completed jobs so can call `Get-PodStatus` on a job that is not a pre-install hook.
- `catch` added for rollback for better error handling.

## [1.0.13] 2024-6-16

### Fixed

- Rollback status not includes in output
- If preHook gets an error, rollback not triggered

## [1.0.12] 2024-6-16

### Fixed

- If preHook is configured to check, but not run in helm, would give a K8s error.

## [1.0.11] 2024-6-7

### Updated

- Dry run title is better, and doesn't collapse in AzDO by default.

## [1.0.10] 2024-5-18

### Added

- Timeout status enum for pod instead of using Unknown
- More test coverage
- GitHub Actions for CI/CD

### Fixed

- Syntax error in the event that probe fails

### Updated

- More accurate statuses on errors.
- Changes for script analyzer.

## [1.0.9] 2024-5-16

### Added

- Allow for only having a prehook, and no deploy by passing in blank for the DeploymentSelector
- Added RollbackStatus to output object indicating if it rolled back or not

### Updated

- run.ps1 `test` task dumps out the status of all tests, and saves it to $global:results
- Get-DeploymentStatus now better handles no items returned from helm status

## [1.0.8] 2024-5-14

### Updated

- Even more hints on expanding logs in AzDO
- Do group error events/logs for AzDO so isn't collapsed in the log

## [1.0.7] 2024-5-13

### Fixed

- Event messages no longer truncates in AzDO, or narrower consoles
- Handle case when error only is in the pod's state, not in events

### Updated

- Check for kubectl and helm in the psm1
- If helm status returns unexpected result, logs it

## [1.0.6] 2024-5-7

### Fixed

- Prehook failure detection updated to catch it more quickly

## [1.0.5] 2024-5-4

### Fixed

- If startup probe fails a bit, it is tolerated instead of bailing on first timeout

### Updated

- In AzDO use "👈 Expand" to help indicate expandable areas in the log.

## [1.0.4] 2024-3-6

### Updated

- Logging improved

## [1.0.3] 2024-3-4

### Updated

- support helm operation in progress

## [1.0.2] 2024-2-23

### Updated

- Improved logging
- Prehook gets pod status
- Tests added

## [1.0.0] 2024-2-23

Initial release
