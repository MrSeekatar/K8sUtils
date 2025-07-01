# if not UTC allow setting hours offset.
$script:UtcOffset = [TimeSpan]::Zero

# helper to get the current time as configured
function Get-CurrentTime {
    param(
        [TimeSpan] $Offset = [TimeSpan]::Zero
    )
    return (Get-Date).Add($script:UtcOffset).Add($Offset)
}