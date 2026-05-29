<#
.SYNOPSIS
Retrieves the value of a nested property from an object using a dot-separated property path.

.DESCRIPTION
Traverses an object (including nested hashtables and PSObjects) to extract the value at the specified property path. Handles missing properties and collections gracefully, with optional error throwing.

.PARAMETER Object
The object to traverse.

.PARAMETER PropertyPath
Dot-separated string specifying the property path (e.g., 'foo.bar.baz').

.PARAMETER ThrowIfNotFound
If specified, throws an error when a property in the path is not found. Otherwise, returns $null.

.OUTPUTS
The value of the property if found; otherwise $null or throws if -ThrowIfNotFound is set.

.EXAMPLE
Get-ObjectPropertyValue -Object $obj -PropertyPath 'foo.bar.baz'

.NOTES
Supports both hashtables/dictionaries and PSObjects. Does not support property access on collections.
#>
function Get-ObjectPropertyValue {
    param (
        [Parameter(Mandatory)]
        [object] $Object,
        [Parameter(Mandatory)]
        [string] $PropertyPath,
        [switch] $ThrowIfNotFound
    )
    Set-StrictMode -Version Latest

    $currentValue = $Object
    foreach ($property in $PropertyPath -split '\.') {
        if ($currentValue -is [System.Collections.IDictionary]) {
            if ($currentValue.Contains($property)) {
                $currentValue = $currentValue[$property]
            } else {
                if ($ThrowIfNotFound) {
                    throw "Property '$property' not found in object."
                }
                return $null
            }
        } elseif ($currentValue -is [System.Collections.IEnumerable] -and -not ($currentValue -is [string])) {
            # If the current value is a collection, we can't access a property on it directly
            if ($ThrowIfNotFound) {
                throw "Property '$property' not found in object."
            }
            return $null
        } else {
            if ($currentValue -and $currentValue.PSObject.Properties[$property]) {
                $currentValue = $currentValue.$property
            } else {
                if ($ThrowIfNotFound) {
                    throw "Property '$property' not found in object."
                }
                return $null
            }
        }
    }
    return $currentValue
}
New-Alias -Name gov -Value Get-ObjectPropertyValue -Force
New-Alias -Name Get-Value -Value Get-ObjectPropertyValue -Force