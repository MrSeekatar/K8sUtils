# if not UTC allow setting hours offset.
$script:UtcOffset = [DateTimeOffset]::Now.Offset

# helper to get the current time as configured
function Get-CurrentTime {
    param(
        [TimeSpan] $Offset = [TimeSpan]::Zero
    )
    return (Get-Date).Subtract($script:UtcOffset).Add($Offset)
}