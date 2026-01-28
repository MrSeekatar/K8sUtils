<#
.SYNOPSIS
Retrieves the synopsis from all exported functions in the K8sUtils module.

.DESCRIPTION
This script imports the K8sUtils module and retrieves the synopsis (brief description)
from the comment-based help of all exported functions. The results are displayed in
a formatted table showing the function name and its synopsis.

.PARAMETER ModuleName
The name of the module to query. Defaults to 'K8sUtils'.

.PARAMETER OutputFormat
The format for displaying results. Options: 'Table', 'List'. Defaults to 'Table'.

.EXAMPLE
.\Get-ModuleSynopsis.ps1

Retrieves and displays the synopsis for all K8sUtils functions in table format.

.EXAMPLE
.\Get-ModuleSynopsis.ps1 -OutputFormat List

Retrieves and displays the synopsis for all K8sUtils functions in list format.
#>
param (
    [Parameter()]
    [string] $ModuleName = 'K8sUtils',

    [Parameter()]
    [ValidateSet('Table', 'List', 'Markdown')]
    [string] $OutputFormat = 'Table'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

try {
    if (!(Get-Module $ModuleName -ErrorAction SilentlyContinue)) {
        Write-Verbose "Module '$ModuleName' must be loaded first."
    }

    # Get all exported functions from the module
    $commands = Get-Command -Module $ModuleName -CommandType Function

    if ($commands.Count -eq 0) {
        Write-Warning "No functions found in module '$ModuleName'."
        return
    }

    Write-Verbose "Found $($commands.Count) function(s) in module '$ModuleName'."

    # Retrieve synopsis for each function
    $results = foreach ($command in $commands) {
        $help = Get-Help $command.Name -ErrorAction SilentlyContinue

        [PSCustomObject]@{
            FunctionName = $command.Name
            Synopsis     = if ($help.Synopsis) { $help.Synopsis } else { "No synopsis available" }
        }
    }

    # Sort results by function name
    $results = $results | Sort-Object FunctionName

    # Display results based on output format
    switch ($OutputFormat) {
        'Table' {
            $results | Format-Table -Property FunctionName, Synopsis -AutoSize -Wrap
        }
        'List' {
            $results | Format-List -Property FunctionName, Synopsis
        }
        'Markdown' {
            $results | ForEach-Object { "| $($_.FunctionName) | $($_.Synopsis) |" }
        }
    }

    Write-Verbose "Synopsis retrieval completed successfully."

} catch {
    Write-Error "An error occurred: $_"
    throw
}
