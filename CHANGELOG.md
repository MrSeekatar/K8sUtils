# Change Log

## [1.0.10] 2024-5-x

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
